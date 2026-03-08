import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants.dart';
import 'cf_challenge_logger.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'network/discourse_dio.dart';

/// cf_clearance 自动续期服务
///
/// 保持一个持久的 HeadlessInAppWebView，加载 Turnstile widget 并设置
/// refresh-expired: "auto"，让 Turnstile 自身驱动刷新循环（默认 290 秒）。
///
/// 通过覆写 window.fetch 拦截 api.js 对 rc 端点的内部调用，
/// 由 Dart 侧 Dio 发起真实请求，再将真实响应回传给 api.js。
class CfClearanceRefreshService {
  static final CfClearanceRefreshService _instance =
      CfClearanceRefreshService._internal();
  factory CfClearanceRefreshService() => _instance;
  CfClearanceRefreshService._internal();

  /// 缓存的 sitekey（来自预热 HTML 或 403 响应体）
  String? _sitekey;

  /// 持久 HeadlessWebView（保持 Turnstile widget 存活）
  HeadlessInAppWebView? _headlessWebView;

  /// WebView 是否已启动
  bool _isRunning = false;

  /// 是否正在调用 rc 端点
  bool _isCallingRc = false;

  /// 连续失败次数
  int _consecutiveFailures = 0;

  /// 最大连续失败次数
  static const int _maxConsecutiveFailures = 3;

  /// Turnstile 首次解题超时
  static const Duration _initialTimeout = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // sitekey 管理
  // ---------------------------------------------------------------------------

  /// 获取当前缓存的 sitekey
  String? get sitekey => _sitekey;

  /// 更新 sitekey（由 PreloadedDataService 或 CfChallengeInterceptor 调用）
  void updateSitekey(String sitekey) {
    if (sitekey.isEmpty) return;
    final changed = _sitekey != sitekey;
    _sitekey = sitekey;
    if (changed) {
      CfChallengeLogger.log(
          '[CfRefresh] sitekey 已更新: ${sitekey.substring(0, 8)}...');
    }
  }

  /// 从 HTML 中提取并更新 sitekey
  void extractAndUpdateSitekey(String html) {
    final match =
        RegExp(r'data-sitekey="([0-9a-zA-Zx_-]+)"').firstMatch(html);
    if (match == null) return;
    final sitekey = match.group(1);
    if (sitekey != null && sitekey.isNotEmpty) {
      updateSitekey(sitekey);
    }
  }

  // ---------------------------------------------------------------------------
  // 生命周期
  // ---------------------------------------------------------------------------

  /// 启动服务：创建持久 WebView，加载 Turnstile
  void start() {
    if (_isRunning) return;
    _consecutiveFailures = 0;
    _startWebView();
  }

  /// 暂停：销毁 WebView（应用进入后台，WebView 可能被系统挂起）
  void pause() {
    if (!_isRunning) return;
    CfChallengeLogger.log('[CfRefresh] 暂停，释放 WebView');
    _disposeWebView();
  }

  /// 恢复：重新创建 WebView（应用回到前台）
  void resume() {
    if (_isRunning) return;
    CfChallengeLogger.log('[CfRefresh] 恢复');
    _consecutiveFailures = 0;
    _startWebView();
  }

  /// 停止服务
  void stop() {
    _disposeWebView();
    _consecutiveFailures = 0;
    CfChallengeLogger.log('[CfRefresh] 服务已停止');
  }

  // ---------------------------------------------------------------------------
  // WebView 管理
  // ---------------------------------------------------------------------------

  /// 启动持久 HeadlessWebView
  void _startWebView() {
    if (_sitekey == null) {
      CfChallengeLogger.log('[CfRefresh] 无 sitekey，跳过启动');
      return;
    }

    // 需要有 cf_clearance 才启动（说明已通过 CF 验证）
    CookieJarService().getCfClearanceCookie().then((cookie) {
      if (cookie == null) {
        CfChallengeLogger.log('[CfRefresh] 无 cf_clearance，跳过启动');
        return;
      }
      _createAndRunWebView();
    });
  }

  /// 创建并运行 HeadlessWebView
  Future<void> _createAndRunWebView() async {
    if (_isRunning || _sitekey == null) return;

    final html = _buildTurnstileHtml(_sitekey!);
    Timer? initialTimer;

    _headlessWebView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: AppConstants.userAgent,
      ),
      onWebViewCreated: (controller) {
        // 核心通道：拦截 api.js 内部的 fetch(/rc/) 调用
        controller.addJavaScriptHandler(
          handlerName: 'onRcIntercepted',
          callback: (args) {
            initialTimer?.cancel();
            initialTimer = null;

            if (args.isNotEmpty && args[0] is Map) {
              final data = args[0] as Map;
              final id = data['id'] as String? ?? '';
              final chlId = data['chlId'] as String?;
              final secondaryToken = data['secondaryToken'] as String?;
              final sitekey = data['sitekey'] as String?;
              _onRcIntercepted(id, chlId, secondaryToken, sitekey);
            }
          },
        );

        // 错误通道
        controller.addJavaScriptHandler(
          handlerName: 'onTurnstileError',
          callback: (args) {
            final error = args.isNotEmpty ? args[0] : 'unknown';
            CfChallengeLogger.log('[CfRefresh] Turnstile 错误: $error');
            _consecutiveFailures++;
            if (_consecutiveFailures >= _maxConsecutiveFailures) {
              CfChallengeLogger.log(
                  '[CfRefresh] 连续失败 $_consecutiveFailures 次，停止服务');
              stop();
            }
          },
        );
      },
      onReceivedError: (controller, request, error) {
        debugPrint('[CfRefresh] WebView 错误: ${error.description}');
      },
    );

    try {
      _isRunning = true;
      CfChallengeLogger.log('[CfRefresh] 启动 Turnstile WebView');

      await _headlessWebView!.run();
      await _headlessWebView!.webViewController?.loadData(
        data: html,
        baseUrl: WebUri(AppConstants.baseUrl),
        mimeType: 'text/html',
        encoding: 'utf-8',
      );

      // 首次解题超时检测
      initialTimer = Timer(_initialTimeout, () {
        CfChallengeLogger.log('[CfRefresh] 首次解题超时');
        _consecutiveFailures++;
      });
    } catch (e) {
      debugPrint('[CfRefresh] WebView 启动失败: $e');
      _isRunning = false;
      await _headlessWebView?.dispose();
      _headlessWebView = null;
    }
  }

  /// 释放 WebView
  Future<void> _disposeWebView() async {
    _isRunning = false;
    final wv = _headlessWebView;
    _headlessWebView = null;
    await wv?.dispose();
  }

  // ---------------------------------------------------------------------------
  // rc 端点处理
  // ---------------------------------------------------------------------------

  /// fetch 拦截回调：api.js 尝试调用 rc 端点，被我们截获
  void _onRcIntercepted(
      String id, String? chlId, String? secondaryToken, String? sitekey) {
    if (_isCallingRc) {
      // 已有 rc 调用进行中，直接返回 503 让 api.js 知道繁忙
      _resolveRcPromise(id, 503, '{}');
      return;
    }

    if (chlId == null || chlId.isEmpty) {
      CfChallengeLogger.log('[CfRefresh] 拦截到 rc 调用但缺少 chlId');
      _resolveRcPromise(id, 400, '{}');
      return;
    }

    // sitekey 优先用拦截到的，fallback 用缓存的
    final effectiveSitekey =
        (sitekey != null && sitekey.isNotEmpty) ? sitekey : _sitekey;
    if (effectiveSitekey == null) {
      CfChallengeLogger.log('[CfRefresh] 无 sitekey，跳过 rc 调用');
      _resolveRcPromise(id, 400, '{}');
      return;
    }

    CfChallengeLogger.log('[CfRefresh] 拦截 rc 调用，chlId: $chlId');

    _callRcEndpoint(id, chlId, secondaryToken, effectiveSitekey);
  }

  /// 调用 CF rc 端点并将真实响应回传给 JS
  Future<void> _callRcEndpoint(
      String id, String chlId, String? secondaryToken, String sitekey) async {
    _isCallingRc = true;
    try {
      final dio = DiscourseDio.create(
        enableCfChallenge: false,
        enableRetry: false,
      );

      final response = await dio.post(
        '/cdn-cgi/challenge-platform/h/g/rc/$chlId',
        data: {
          if (secondaryToken != null && secondaryToken.isNotEmpty)
            'secondaryToken': secondaryToken,
          'sitekey': sitekey,
        },
        options: Options(
          headers: {
            'Origin': AppConstants.baseUrl,
            'Referer': '${AppConstants.baseUrl}/',
          },
          extra: {
            'skipCfChallenge': true,
            'skipCsrf': true,
            'isSilent': true,
          },
          validateStatus: (status) => status != null,
        ),
      );

      final statusCode = response.statusCode ?? 500;
      final body = response.data?.toString() ?? '{}';
      CfChallengeLogger.log('[CfRefresh] rc 端点响应: $statusCode');

      // 将真实响应回传给 JS 的 pending Promise
      _resolveRcPromise(id, statusCode, body);

      // 验证 cf_clearance 是否已更新
      final cfClearance = await CookieJarService().getCfClearance();
      if (cfClearance != null && cfClearance.isNotEmpty) {
        _consecutiveFailures = 0;
        CfChallengeLogger.log('[CfRefresh] cf_clearance 续期成功');
      } else {
        _consecutiveFailures++;
        CfChallengeLogger.log(
            '[CfRefresh] cf_clearance 未更新 (连续失败 $_consecutiveFailures 次)');
        _checkAndStopIfNeeded();
      }
    } catch (e) {
      CfChallengeLogger.log('[CfRefresh] rc 端点调用异常: $e');
      _resolveRcPromise(id, 500, '{}');
      _consecutiveFailures++;
      _checkAndStopIfNeeded();
    } finally {
      _isCallingRc = false;
    }
  }

  /// 通过 evaluateJavascript 将真实响应回传给 JS 的 pending Promise
  void _resolveRcPromise(String id, int statusCode, String body) {
    // 转义 body 中的特殊字符，防止 JS 注入
    final escapedBody = body
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
    _headlessWebView?.webViewController?.evaluateJavascript(
      source: "window._resolveRc('$id', $statusCode, '$escapedBody')",
    );
  }

  /// 检查是否应该停止服务
  void _checkAndStopIfNeeded() {
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      CfChallengeLogger.log('[CfRefresh] 连续失败过多，停止服务');
      stop();
    }
  }

  // ---------------------------------------------------------------------------
  // HTML 模板
  // ---------------------------------------------------------------------------

  /// 构建 Turnstile HTML
  ///
  /// 在 api.js 加载前覆写 window.fetch，拦截 /rc/ 请求。
  /// JS 端创建 pending Promise，Dart 调完 Dio 后通过
  /// evaluateJavascript 调用 window._resolveRc() 回传真实响应。
  String _buildTurnstileHtml(String sitekey) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script>
    // 在 api.js 加载前覆写 fetch，拦截 rc 端点调用
    var _originalFetch = window.fetch;
    var _pendingRc = {};
    var _rcId = 0;

    window.fetch = function(url, options) {
      if (typeof url === 'string' &&
          url.indexOf('/cdn-cgi/challenge-platform/') !== -1 &&
          url.indexOf('/rc/') !== -1) {
        var id = 'rc_' + (++_rcId);
        var parts = url.split('/rc/');
        var chlId = parts.length > 1 ? parts[1].split('?')[0] : '';
        var body = {};
        try { body = JSON.parse(options.body); } catch(e) {}

        // 转发给 Dart，由 Dart 发起真实请求
        window.flutter_inappwebview.callHandler('onRcIntercepted', {
          id: id,
          chlId: chlId,
          secondaryToken: body.secondaryToken || '',
          sitekey: body.sitekey || ''
        });

        // 返回 Promise，等 Dart 回传真实响应后 resolve
        return new Promise(function(resolve) {
          _pendingRc[id] = resolve;
        });
      }
      return _originalFetch.apply(this, arguments);
    };

    // Dart 调用此函数回传真实响应
    window._resolveRc = function(id, status, body) {
      if (_pendingRc[id]) {
        _pendingRc[id](new Response(body || '{}', { status: status }));
        delete _pendingRc[id];
      }
    };
  </script>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileLoad" async defer></script>
</head>
<body>
  <div id="turnstile-container"></div>
  <script>
    function onTurnstileLoad() {
      try {
        turnstile.render('#turnstile-container', {
          sitekey: '$sitekey',
          appearance: 'interaction-only',
          'refresh-expired': 'auto',
          'error-callback': function(error) {
            window.flutter_inappwebview.callHandler('onTurnstileError', error || 'render_error');
          }
        });
      } catch(e) {
        window.flutter_inappwebview.callHandler('onTurnstileError', e.toString());
      }
    }
  </script>
</body>
</html>
''';
  }
}
