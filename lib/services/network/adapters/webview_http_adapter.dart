import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../constants.dart';
import '../cookie/boundary_sync_service.dart';
import '../cookie/cookie_jar_service.dart';
import '../cookie/raw_set_cookie_queue.dart';
import '../../webview_settings.dart';
import '../../windows_webview_environment_service.dart';

/// WebView HTTP 适配器
///
/// 使用 InAppWebView 的 JS fetch() 发起 HTTP 请求。
/// 请求经过真正的 Chrome/WebKit 内核，TLS 指纹与浏览器完全一致，
/// 可绕过 Cloudflare Bot Management 等基于指纹的检测。
///
/// 全平台支持：Android (Chrome WebView)、iOS/macOS (WKWebView)、
/// Windows (WebView2)、Linux (WebKitGTK)。
class WebViewHttpAdapter implements HttpClientAdapter {
  static const Set<String> _forbiddenBrowserHeaders = {
    'accept-charset',
    'accept-encoding',
    'access-control-request-headers',
    'access-control-request-method',
    'connection',
    'content-length',
    'cookie',
    'cookie2',
    'date',
    'dnt',
    'expect',
    'host',
    'keep-alive',
    'origin',
    'referer',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'user-agent',
    'via',
  };

  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _controller;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  Future<void>? _activeCriticalCookieSync;
  DateTime? _lastCriticalCookieSyncAt;

  final Map<String, Completer<String>> _pendingRequests = {};
  int _requestId = 0;

  /// 初始化 WebView
  Future<void> initialize() async {
    if (_isInitialized && _controller != null) return;
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      await _initCompleter!.future;
      return;
    }

    final initCompleter = Completer<void>();
    _initCompleter = initCompleter;

    try {
      _headlessWebView = HeadlessInAppWebView(
        // Windows 需要 WebView2 环境，其他平台传 null
        webViewEnvironment: Platform.isWindows
            ? WindowsWebViewEnvironmentService.instance.environment
            : null,
        // 加载主站页面（而非 about:blank），确保 cookie store 已初始化
        initialUrlRequest: URLRequest(url: WebUri(AppConstants.baseUrl)),
        initialSettings: WebViewSettings.headless,
        onReceivedServerTrustAuthRequest: (_, challenge) =>
            WebViewSettings.handleServerTrustAuthRequest(challenge),
        onWebViewCreated: (controller) {
          _controller = controller;

          controller.addJavaScriptHandler(
            handlerName: 'fetchResult',
            callback: (args) {
              if (args.isNotEmpty && args[0] is Map) {
                final data = args[0] as Map;
                final requestId = data['requestId']?.toString();
                final result = data['result']?.toString() ?? '';

                if (requestId != null &&
                    _pendingRequests.containsKey(requestId)) {
                  _pendingRequests[requestId]!.complete(result);
                  _pendingRequests.remove(requestId);
                }
              }
            },
          );

          debugPrint('[WebViewAdapter] Controller created');
        },
        onLoadStop: (controller, url) {
          debugPrint('[WebViewAdapter] Page loaded: $url');
          if (!initCompleter.isCompleted) {
            initCompleter.complete();
          }
        },
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame != false && !initCompleter.isCompleted) {
            initCompleter.completeError(
              StateError(
                'WebView init failed: ${error.type} ${error.description}',
              ),
            );
          }
        },
      );

      await _headlessWebView!.run();

      await initCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('WebView init timeout');
        },
      );

      _isInitialized = true;
      debugPrint('[WebViewAdapter] Initialized');
    } catch (e) {
      debugPrint('[WebViewAdapter] Init failed: $e');
      close(force: true);
      rethrow;
    } finally {
      if (identical(_initCompleter, initCompleter) && !_isInitialized) {
        _initCompleter = null;
      }
    }
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!_isInitialized || _controller == null) {
      await initialize();
    }

    if (_controller == null) {
      throw DioException(
        requestOptions: options,
        error: 'WebView controller not available',
        type: DioExceptionType.unknown,
      );
    }

    final url = options.uri.toString();
    final method = options.method.toUpperCase();
    final requestId = (++_requestId).toString();
    final requestUri = Uri.parse(url);
    final baseUri = Uri.parse(AppConstants.baseUrl);
    final shouldSyncAppCookies = _shouldSyncAppCookies(requestUri, baseUri);

    if (shouldSyncAppCookies) {
      final written = await RawSetCookieQueue.instance.flushToWebView();
      if (written == 0) {
        await _syncCookiesFromJar(requestUri);
      }
    }

    // 非应用站点的备选路径：通过 CookieManager 写入 cookie
    final cookieHeader = options.headers['Cookie']?.toString();
    if (!shouldSyncAppCookies &&
        cookieHeader != null &&
        cookieHeader.isNotEmpty) {
      await _syncCookiesViaCookieManager(url, cookieHeader);
    }

    // 构建 headers（移除 Cookie，由 WebView 自动处理）
    final headersMap = _buildBrowserSafeHeaders(options.headers);

    // 构建 body
    String? bodyJson;
    if (options.data != null && method != 'GET' && method != 'HEAD') {
      if (options.data is Map || options.data is List) {
        bodyJson = jsonEncode(options.data);
      } else {
        bodyJson = options.data.toString();
      }
    }

    final completer = Completer<String>();
    _pendingRequests[requestId] = completer;

    final isBinary = options.responseType == ResponseType.bytes;

    final script = '''
      (async function() {
        try {
          const fetchOptions = {
            method: '$method',
            headers: ${jsonEncode(headersMap)},
            credentials: 'include'
          };
          ${bodyJson != null ? "fetchOptions.body = ${jsonEncode(bodyJson)};" : ""}

          const response = await fetch('$url', fetchOptions);

          let bodyData;
          let isBase64 = false;

          if ($isBinary) {
            const buffer = await response.arrayBuffer();
            let binary = '';
            const bytes = new Uint8Array(buffer);
            const len = bytes.byteLength;
            for (let i = 0; i < len; i++) {
              binary += String.fromCharCode(bytes[i]);
            }
            bodyData = window.btoa(binary);
            isBase64 = true;
          } else {
            bodyData = await response.text();
          }

          const headersObj = {};
          response.headers.forEach((v, k) => headersObj[k] = v);

          const result = JSON.stringify({
            ok: true,
            status: response.status,
            statusText: response.statusText,
            headers: headersObj,
            body: bodyData,
            isBase64: isBase64
          });

          window.flutter_inappwebview.callHandler('fetchResult', {
            requestId: '$requestId',
            result: result
          });
        } catch (e) {
          window.flutter_inappwebview.callHandler('fetchResult', {
            requestId: '$requestId',
            result: JSON.stringify({ok: false, error: e.toString()})
          });
        }
      })();
    ''';

    debugPrint(
      '[WebViewAdapter] Fetching: $method $url (id: $requestId, binary: $isBinary)',
    );

    await _controller!.evaluateJavascript(source: script);

    // 超时从 RequestOptions 读取，默认 30 秒
    final timeout =
        options.receiveTimeout ??
        options.connectTimeout ??
        const Duration(seconds: 30);

    final resultStr = await completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(requestId);
        throw DioException(
          requestOptions: options,
          error: 'WebView request timeout',
          type: DioExceptionType.receiveTimeout,
        );
      },
    );

    final responseData = jsonDecode(resultStr) as Map<String, dynamic>;

    if (responseData['ok'] != true) {
      throw DioException(
        requestOptions: options,
        error: responseData['error']?.toString() ?? 'Unknown error',
        type: DioExceptionType.unknown,
      );
    }

    final statusCode = responseData['status'] as int? ?? 200;
    final bodyContent = responseData['body'] as String? ?? '';
    final isBase64 = responseData['isBase64'] as bool? ?? false;

    final responseHeaders = <String, List<String>>{};

    if (responseData['headers'] is Map) {
      (responseData['headers'] as Map).forEach((key, value) {
        responseHeaders[key.toString()] = [value.toString()];
      });
    }

    if (shouldSyncAppCookies) {
      await _syncCriticalCookiesBackToJar(
        url,
        force: method != 'GET' && method != 'HEAD',
      );
    }

    debugPrint('[WebViewAdapter] Response: $statusCode (binary: $isBase64)');

    if (isBase64) {
      final bytes = base64Decode(bodyContent);
      return ResponseBody.fromBytes(
        bytes,
        statusCode,
        headers: responseHeaders,
      );
    } else {
      return ResponseBody.fromString(
        bodyContent,
        statusCode,
        headers: responseHeaders,
      );
    }
  }

  @override
  void close({bool force = false}) {
    _headlessWebView?.dispose();
    _headlessWebView = null;
    _controller = null;
    _isInitialized = false;
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      _initCompleter!.completeError(StateError('WebView adapter closed'));
    }
    _initCompleter = null;
    _activeCriticalCookieSync = null;
    _lastCriticalCookieSyncAt = null;
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError('WebView adapter closed');
      }
    }
    _pendingRequests.clear();
  }

  bool _shouldSyncAppCookies(Uri requestUri, Uri baseUri) {
    final requestHost = requestUri.host;
    final baseHost = baseUri.host;
    if (requestHost.isEmpty || baseHost.isEmpty) {
      return false;
    }
    return requestHost == baseHost || requestHost.endsWith('.$baseHost');
  }

  /// 通过全平台 CookieManager API 写入 cookie
  Future<void> _syncCookiesViaCookieManager(
    String url,
    String cookieHeader,
  ) async {
    try {
      final cookieManager = _resolveCookieManager();
      final webUri = WebUri(url);
      final cookies = cookieHeader.split('; ');
      for (final cookie in cookies) {
        final parts = cookie.split('=');
        if (parts.length >= 2) {
          final name = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          await cookieManager.setCookie(
            url: webUri,
            name: name,
            value: value,
          );
        }
      }
    } catch (e) {
      debugPrint('[WebViewAdapter] Failed to sync cookies: $e');
    }
  }

  Map<String, String> _buildBrowserSafeHeaders(Map<String, dynamic> headers) {
    final headersMap = <String, String>{};
    final droppedHeaders = <String>[];

    headers.forEach((key, value) {
      if (value == null) return;
      if (_isForbiddenBrowserHeader(key)) {
        droppedHeaders.add(key);
        return;
      }
      headersMap[key] = value.toString();
    });

    if (droppedHeaders.isNotEmpty) {
      debugPrint(
        '[WebViewAdapter] Dropped browser-managed headers: '
        '${droppedHeaders.join(', ')}',
      );
    }

    return headersMap;
  }

  bool _isForbiddenBrowserHeader(String key) {
    final normalized = key.trim().toLowerCase();
    if (_forbiddenBrowserHeaders.contains(normalized)) {
      return true;
    }
    return normalized.startsWith('sec-') || normalized.startsWith('proxy-');
  }

  CookieManager _resolveCookieManager() {
    return Platform.isWindows
        ? WindowsWebViewEnvironmentService.instance.cookieManager
        : CookieManager.instance();
  }

  Future<void> _syncCookiesFromJar(Uri requestUri) async {
    final jar = CookieJarService();
    if (!jar.isInitialized) {
      await jar.initialize();
    }

    final cookies = await jar.loadCanonicalCookiesForRequest(requestUri);
    if (cookies.isEmpty) return;

    final cookieManager = _resolveCookieManager();
    var synced = 0;

    for (final cookie in cookies) {
      try {
        final cookieUri = Uri(
          scheme: requestUri.scheme,
          host: requestUri.host,
          port: requestUri.hasPort ? requestUri.port : null,
          path: cookie.path.isEmpty ? '/' : cookie.path,
        );

        await cookieManager.setCookie(
          url: WebUri(cookieUri.toString()),
          name: cookie.name,
          value: cookie.value,
          path: cookie.path.isEmpty ? '/' : cookie.path,
          domain: cookie.hostOnly ? null : cookie.domain,
          expiresDate: cookie.expiresAt?.millisecondsSinceEpoch,
          maxAge: cookie.maxAge,
          isSecure: cookie.secure,
          isHttpOnly: cookie.httpOnly,
          sameSite: _toWebViewSameSite(cookie.sameSite),
        );
        synced++;
      } catch (e) {
        debugPrint(
          '[WebViewAdapter] Failed to backfill cookie ${cookie.name} to WebView: $e',
        );
      }
    }

    if (synced > 0) {
      debugPrint('[WebViewAdapter] Backfilled $synced cookies from jar');
    }
  }

  HTTPCookieSameSitePolicy? _toWebViewSameSite(CookieSameSite sameSite) {
    switch (sameSite) {
      case CookieSameSite.lax:
        return HTTPCookieSameSitePolicy.LAX;
      case CookieSameSite.strict:
        return HTTPCookieSameSitePolicy.STRICT;
      case CookieSameSite.none:
        return HTTPCookieSameSitePolicy.NONE;
      case CookieSameSite.unspecified:
        return null;
    }
  }

  Future<void> _syncCriticalCookiesBackToJar(
    String currentUrl, {
    bool force = false,
  }) async {
    final controller = _controller;
    if (controller == null) return;

    if (!force) {
      final lastSyncAt = _lastCriticalCookieSyncAt;
      if (lastSyncAt != null &&
          DateTime.now().difference(lastSyncAt) <
              const Duration(milliseconds: 800)) {
        final active = _activeCriticalCookieSync;
        if (active != null) {
          await active;
        }
        return;
      }
    }

    final active = _activeCriticalCookieSync;
    if (active != null) {
      await active;
      return;
    }

    final future = BoundarySyncService.instance.syncFromWebView(
      currentUrl: currentUrl,
      controller: controller,
      cookieNames: CookieJarService.criticalCookieNames,
    );

    _activeCriticalCookieSync = future.whenComplete(() {
      _lastCriticalCookieSyncAt = DateTime.now();
      _activeCriticalCookieSync = null;
    });

    await _activeCriticalCookieSync!;
  }
}
