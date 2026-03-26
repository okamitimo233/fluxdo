import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../constants.dart';
import '../cookie/cookie_jar_service.dart';
import '../cookie/cookie_write_through.dart';
import '../../webview_settings.dart';
import '../../windows_webview_environment_service.dart';

/// WebView HTTP 适配器
/// 使用 InAppWebView 发起 HTTP 请求，完全绕过 Cloudflare 验证
class WebViewHttpAdapter implements HttpClientAdapter {
  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _controller;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  // 用于接收 JS 回调结果
  final Map<String, Completer<String>> _pendingRequests = {};
  int _requestId = 0;

  /// 初始化 WebView
  Future<void> initialize() async {
    if (_isInitialized && _controller != null) return;

    _initCompleter = Completer<void>();

    _headlessWebView = HeadlessInAppWebView(
      webViewEnvironment: WindowsWebViewEnvironmentService.instance.environment,
      initialUrlRequest: URLRequest(url: WebUri(AppConstants.baseUrl)),
      initialSettings: WebViewSettings.headless,
      onReceivedServerTrustAuthRequest: (_, challenge) =>
          WebViewSettings.handleServerTrustAuthRequest(challenge),
      onWebViewCreated: (controller) {
        _controller = controller;

        // 添加 JS Handler 来接收异步结果
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
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _isInitialized = true;
          _initCompleter!.complete();
        }
      },
    );

    await _headlessWebView!.run();

    await _initCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => debugPrint('[WebViewAdapter] Init timeout'),
    );

    debugPrint('[WebViewAdapter] Initialized');
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
      await CookieWriteThrough.instance.seedCriticalCookies(
        controller: _controller,
      );
      await CookieWriteThrough.instance.barrier();
    }

    // 非应用站点的备选路径：根据请求头尽力补 Cookie。
    // 应用站点统一依赖 CookieJarService 的 WebView 同步，避免 header 与 CookieStore 脱节。
    final cookieHeader = options.headers['Cookie']?.toString();
    if (!shouldSyncAppCookies &&
        cookieHeader != null &&
        cookieHeader.isNotEmpty) {
      // 1. 仅在同域时通过 JS 设置 (避免跨域写入到当前页面域)
      if (requestUri.host == baseUri.host) {
        final setCookieJs = cookieHeader
            .split('; ')
            .map((c) => "document.cookie = '$c';")
            .join('\n');
        await _controller!.evaluateJavascript(source: setCookieJs);
      }

      // 2. 尝试通过 CookieManager 设置 (对 HttpOnly 有效，关键！)
      try {
        final cookieManager =
            WindowsWebViewEnvironmentService.instance.cookieManager;
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
        debugPrint(
          '[WebViewAdapter] Failed to sync cookies via CookieManager: $e',
        );
      }
    }

    // 构建 headers（移除 Cookie，由 WebView 自动处理）
    final headersMap = <String, String>{};
    options.headers.forEach((key, value) {
      if (value != null && key != 'Cookie') headersMap[key] = value.toString();
    });

    // 构建 body
    String? bodyJson;
    if (options.data != null && method != 'GET' && method != 'HEAD') {
      if (options.data is Map || options.data is List) {
        bodyJson = jsonEncode(options.data);
      } else {
        bodyJson = options.data.toString();
      }
    }

    // 创建等待器
    final completer = Completer<String>();
    _pendingRequests[requestId] = completer;

    // 检查是否需要二进制响应
    final isBinary = options.responseType == ResponseType.bytes;

    // 构建脚本 - 使用 JS Handler 回调
    final script =
        '''
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

    // 等待结果
    final resultStr = await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        throw DioException(
          requestOptions: options,
          error: 'Request timeout',
          type: DioExceptionType.connectionTimeout,
        );
      },
    );

    // print('[WebViewAdapter] Got result: ${resultStr.substring(0, resultStr.length > 100 ? 100 : resultStr.length)}...');

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

    debugPrint('[WebViewAdapter] Response: $statusCode (binary: $isBase64)');

    if (shouldSyncAppCookies) {
      await CookieJarService().syncFromWebView(
        currentUrl: url,
        controller: _controller,
      );
    }

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
}
