import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../constants.dart';
import '../../windows_webview_environment_service.dart';
import 'cookie_jar_service.dart';
import 'strategy/platform_cookie_strategy.dart';

/// Cookie Write-Through 服务
/// Dio 收到 Set-Cookie 后，实时推送关键 cookie 到 WebView，
/// 避免 CookieJar 和 WebView 之间的不一致。
class CookieWriteThrough {
  static final instance = CookieWriteThrough._();
  CookieWriteThrough._();

  Completer<void>? _pendingWrite;

  /// Dio 收到 Set-Cookie 后调用（在 AppCookieManager.saveCookies 内）
  /// 只处理关键 cookie，非关键 cookie 不推送
  Future<void> writeThrough(List<io.Cookie> cookies, Uri uri) async {
    final criticals =
        cookies.where((c) => CookieJarService.isCriticalCookie(c.name)).toList();
    if (criticals.isEmpty) return;

    final completer = Completer<void>();
    _pendingWrite = completer;
    try {
      final strategy = PlatformCookieStrategy.create();
      final webViewCookieManager =
          WindowsWebViewEnvironmentService.instance.cookieManager;
      final baseHost = Uri.parse(AppConstants.baseUrl).host;

      for (final cookie in criticals) {
        final value = CookieValueCodec.decode(cookie.value);
        final normalizedDomain =
            CookieJarService.normalizeWebViewCookieDomain(cookie.domain);
        final host = normalizedDomain ?? baseHost;
        final url = WebUri('https://$host');

        // 先删除旧值（含 domain 变体）
        for (final domain in strategy.buildDeleteDomainVariants('.$host')) {
          try {
            await webViewCookieManager.deleteCookie(
              url: url,
              name: cookie.name,
              domain: domain,
              path: cookie.path ?? '/',
            );
          } catch (_) {}
        }
        for (final domain in strategy.buildDeleteDomainVariants(host)) {
          try {
            await webViewCookieManager.deleteCookie(
              url: url,
              name: cookie.name,
              domain: domain,
              path: cookie.path ?? '/',
            );
          } catch (_) {}
        }
        // 删除 host-only 变体
        try {
          await webViewCookieManager.deleteCookie(
            url: url,
            name: cookie.name,
            path: cookie.path ?? '/',
          );
        } catch (_) {}

        // 写入新值
        try {
          await webViewCookieManager.setCookie(
            url: url,
            name: cookie.name,
            value: value.isEmpty ? ' ' : value,
            domain: cookie.domain,
            path: cookie.path ?? '/',
            isSecure: cookie.secure,
            isHttpOnly: cookie.httpOnly,
            expiresDate: cookie.expires?.millisecondsSinceEpoch,
            sameSite: (cookie.httpOnly && cookie.secure)
                ? HTTPCookieSameSitePolicy.NONE
                : null,
          );
        } catch (e) {
          debugPrint('[CookieWriteThrough] 写入 ${cookie.name} 失败: $e');
        }
      }

      debugPrint(
        '[CookieWriteThrough] 已推送 ${criticals.length} 个关键 cookie 到 WebView',
      );
    } catch (e) {
      debugPrint('[CookieWriteThrough] writeThrough 失败: $e');
    } finally {
      completer.complete();
      _pendingWrite = null;
    }
  }

  /// WebView 加载前等待在飞写入完成
  Future<void> barrier({Duration timeout = const Duration(seconds: 3)}) async {
    final pending = _pendingWrite;
    if (pending == null) return;
    await pending.future.timeout(timeout, onTimeout: () {});
  }

  /// 冷启动时从 CookieJar 注入关键 cookie 到 WebView
  Future<void> seedCriticalCookies({
    InAppWebViewController? controller,
  }) async {
    final jar = CookieJarService();
    if (!jar.isInitialized) await jar.initialize();

    final strategy = PlatformCookieStrategy.create();
    final webViewCookieManager =
        WindowsWebViewEnvironmentService.instance.cookieManager;
    final baseHost = Uri.parse(AppConstants.baseUrl).host;

    for (final name in const ['_t', '_forum_session', 'cf_clearance']) {
      final cookie = await _loadCriticalCookie(jar, name);
      if (cookie == null) continue;

      final value = CookieValueCodec.decode(cookie.value);
      if (value.isEmpty) continue;

      final normalizedDomain =
          CookieJarService.normalizeWebViewCookieDomain(cookie.domain);
      final host = normalizedDomain ?? baseHost;

      // Windows 通过 CDP 写入
      if (io.Platform.isWindows && controller != null) {
        await _seedViaCDP(controller, cookie, value, host, strategy);
        continue;
      }

      // 其他平台通过 CookieManager 写入
      final url = WebUri('https://$host');

      // 先删除旧值
      for (final domain in strategy.buildDeleteDomainVariants('.$host')) {
        try {
          await webViewCookieManager.deleteCookie(
            url: url,
            name: name,
            domain: domain,
            path: cookie.path ?? '/',
          );
        } catch (_) {}
      }
      for (final domain in strategy.buildDeleteDomainVariants(host)) {
        try {
          await webViewCookieManager.deleteCookie(
            url: url,
            name: name,
            domain: domain,
            path: cookie.path ?? '/',
          );
        } catch (_) {}
      }
      try {
        await webViewCookieManager.deleteCookie(
          url: url,
          name: name,
          path: cookie.path ?? '/',
        );
      } catch (_) {}

      // 写入新值
      try {
        await webViewCookieManager.setCookie(
          url: url,
          name: name,
          value: value,
          domain: cookie.domain,
          path: cookie.path ?? '/',
          isSecure: cookie.secure,
          isHttpOnly: cookie.httpOnly,
          expiresDate: cookie.expires?.millisecondsSinceEpoch,
          sameSite: (cookie.httpOnly && cookie.secure)
              ? HTTPCookieSameSitePolicy.NONE
              : null,
        );
      } catch (e) {
        debugPrint('[CookieWriteThrough] seed $name 失败: $e');
      }
    }

    debugPrint('[CookieWriteThrough] seedCriticalCookies 完成');
  }

  /// 从 CookieJar 加载关键 cookie 的原始对象
  Future<io.Cookie?> _loadCriticalCookie(
    CookieJarService jar,
    String name,
  ) async {
    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final cookies = await jar.cookieJar.loadForRequest(uri);

      io.Cookie? fallback;
      for (final cookie in cookies) {
        if (cookie.name == name && cookie.value.isNotEmpty) {
          // 优先返回 domain cookie（WebView 同步来源更权威）
          if (cookie.domain != null) return cookie;
          fallback ??= cookie;
        }
      }
      return fallback;
    } catch (e) {
      debugPrint('[CookieWriteThrough] 加载 $name 失败: $e');
      return null;
    }
  }

  /// Windows CDP 写入单个 cookie
  Future<void> _seedViaCDP(
    InAppWebViewController controller,
    io.Cookie cookie,
    String value,
    String host,
    PlatformCookieStrategy strategy,
  ) async {
    final normalizedDomain =
        CookieJarService.normalizeWebViewCookieDomain(cookie.domain);

    String cdpUrl;
    String? cdpDomain;
    if (normalizedDomain != null) {
      cdpUrl = 'https://$normalizedDomain';
      cdpDomain = cookie.domain!.startsWith('.')
          ? cookie.domain
          : '.$normalizedDomain';
    } else {
      cdpUrl = 'https://$host';
      cdpDomain = null;
    }

    try {
      // 确保 Network domain 已启用
      try {
        await controller.callDevToolsProtocolMethod(
          methodName: 'Network.enable',
          parameters: {},
        );
      } catch (_) {}

      // 删除旧 cookie
      await controller.callDevToolsProtocolMethod(
        methodName: 'Network.deleteCookies',
        parameters: {
          'name': cookie.name,
          'url': cdpUrl,
          if (cdpDomain != null) 'domain': cdpDomain,
          'path': cookie.path ?? '/',
        },
      );

      // 写入新 cookie
      final params = <String, dynamic>{
        'url': cdpUrl,
        'name': cookie.name,
        'value': value.isEmpty ? ' ' : value,
        'path': cookie.path ?? '/',
        'secure': cookie.secure,
        'httpOnly': cookie.httpOnly,
      };
      if (cdpDomain != null) {
        params['domain'] = cdpDomain;
      }
      if (cookie.expires != null) {
        params['expires'] = cookie.expires!.millisecondsSinceEpoch / 1000.0;
      }
      if (cookie.httpOnly && cookie.secure) {
        params['sameSite'] = 'None';
      }

      await controller.callDevToolsProtocolMethod(
        methodName: 'Network.setCookie',
        parameters: params,
      );
    } catch (e) {
      debugPrint('[CookieWriteThrough] CDP seed ${cookie.name} 失败: $e');
    }
  }
}
