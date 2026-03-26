import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../constants.dart';
import '../../cf_challenge_logger.dart';
import '../../windows_webview_environment_service.dart';
import 'cookie_diagnostics.dart';
import 'cookie_jar_service.dart';
import 'cookie_sync_context.dart';
import 'strategy/platform_cookie_strategy.dart';

/// Cookie 同步编排器
/// 负责 WebView ↔ CookieJar 的双向同步，委托平台策略处理差异
class CookieSyncCoordinator {
  CookieSyncCoordinator({
    required this.jar,
    required this.strategy,
  });

  final CookieJarService jar;
  final PlatformCookieStrategy strategy;

  // ---------------------------------------------------------------------------
  // syncFromWebView：WebView → CookieJar
  // ---------------------------------------------------------------------------

  /// 从 WebView 同步 Cookie 到 CookieJar
  Future<void> syncFromWebView(CookieSyncContext ctx) async {
    try {
      // Windows + controller 可用时，通过 CDP 读取
      if (io.Platform.isWindows && ctx.controller != null) {
        await _syncFromWebViewViaCDP(ctx);
        return;
      }

      final webViewCookies = await strategy.readCookiesFromWebView(ctx);

      if (CfChallengeLogger.isEnabled) {
        CfChallengeLogger.logCookieSync(
          direction: 'WebView -> CookieJar',
          cookies: webViewCookies.map((snapshot) {
            final wc = snapshot.cookie;
            return CookieLogEntry(
              name: wc.name,
              domain: wc.domain,
              path: wc.path,
              expires: CookieJarService.parseWebViewCookieExpires(
                wc.expiresDate,
              ),
              valueLength: wc.value.length,
            );
          }).toList(),
        );
      }

      if (webViewCookies.isEmpty) {
        if (io.Platform.isWindows) {
          debugPrint(
            '[CookieJar][Windows] syncFromWebView 未读取到任何 Cookie: '
            'userDataFolder='
            '${WindowsWebViewEnvironmentService.instance.userDataFolder ?? "<default>"}',
          );
        }
        return;
      }

      // 按 URI 分桶、去重
      final bucketedCookies = <Uri, Map<String, io.Cookie>>{};

      for (final snapshot in webViewCookies) {
        final wc = snapshot.cookie;
        if (ctx.cookieNames != null && !ctx.cookieNames!.contains(wc.name)) {
          continue;
        }
        final rawDomain = wc.domain?.trim();
        final normalizedDomain =
            CookieJarService.normalizeWebViewCookieDomain(rawDomain);
        final shouldPersistAsDomainCookie =
            _shouldPersistWebViewDomainCookie(
          rawDomain: rawDomain,
          normalizedDomain: normalizedDomain,
          sourceHosts: snapshot.sourceHosts,
        );
        String? domainAttr;
        var hostForUri = snapshot.primaryHost;

        if (normalizedDomain != null) {
          hostForUri = normalizedDomain;
          if (shouldPersistAsDomainCookie) {
            domainAttr = '.$normalizedDomain';
          }
        }

        // Dart Cookie 构造函数严格遵循 RFC 6265，对不合规值使用编码存储
        io.Cookie cookie;
        try {
          cookie = io.Cookie(wc.name, wc.value)
            ..path = wc.path ?? '/'
            ..secure = wc.isSecure ?? false
            ..httpOnly = wc.isHttpOnly ?? false;
        } catch (_) {
          cookie = io.Cookie(wc.name, CookieValueCodec.encode(wc.value))
            ..path = wc.path ?? '/'
            ..secure = wc.isSecure ?? false
            ..httpOnly = wc.isHttpOnly ?? false;
        }

        if (domainAttr != null) {
          cookie.domain = domainAttr;
        }
        final expires = CookieJarService.parseWebViewCookieExpires(
          wc.expiresDate,
        );
        if (expires != null) {
          cookie.expires = expires;
        }

        // 跳过已过期的 cookie
        if (cookie.expires != null &&
            cookie.expires!.isBefore(DateTime.now())) {
          debugPrint(
            '[CookieJar] syncFromWebView: 跳过已过期 cookie ${cookie.name}',
          );
          continue;
        }

        // 跳过空值的关键 cookie
        if (cookie.value.isEmpty &&
            CookieJarService.isCriticalCookie(cookie.name)) {
          debugPrint(
            '[CookieJar] syncFromWebView: 跳过空值关键 cookie ${cookie.name}',
          );
          continue;
        }

        final bucketUri = Uri(scheme: ctx.baseUri.scheme, host: hostForUri);
        final dedupeKey =
            '${cookie.name}|${cookie.path}|${cookie.domain ?? hostForUri}';
        bucketedCookies.putIfAbsent(
          bucketUri,
          () => <String, io.Cookie>{},
        )[dedupeKey] = cookie;
      }

      // Bug #5 fix：先清掉 CookieJar 中关键 cookie 旧值，再写入新值
      // 确保同名不存在 domain 类型冲突的副本
      final namesAboutToSync = <String>{};
      for (final cookies in bucketedCookies.values) {
        for (final cookie in cookies.values) {
          if (CookieJarService.isCriticalCookie(cookie.name)) {
            namesAboutToSync.add(cookie.name);
          }
        }
      }
      for (final name in namesAboutToSync) {
        await jar.deleteCookie(name);
      }

      var totalSynced = 0;
      for (final entry in bucketedCookies.entries) {
        final cookies = entry.value.values.toList();
        if (cookies.isEmpty) continue;
        await jar.cookieJar.saveFromResponse(entry.key, cookies);
        totalSynced += cookies.length;
      }

      // Bug #5 fix：写入后再次检查关键 cookie，清理残留的冲突副本
      await _cleanupConflictingCriticalCookies(namesAboutToSync, ctx);

      debugPrint('[CookieJar] Synced $totalSynced cookies from WebView');
      if (io.Platform.isWindows) {
        await CookieDiagnostics.logWindowsCookieSyncStatus(
          'syncFromWebView',
          jar: jar,
          ctx: ctx,
          webViewCookies: webViewCookies.map((s) => s.cookie).toList(),
        );
      }
    } catch (e) {
      debugPrint('[CookieJar] Failed to sync from WebView: $e');
    }
  }

  /// 将当前 WebView 控制器里的关键实时 Cookie 直接回写到 CookieJar
  Future<void> syncCriticalCookiesFromController(
    InAppWebViewController controller,
    CookieSyncContext ctx, {
    Set<String>? cookieNames,
  }) async {
    if (!io.Platform.isWindows && !io.Platform.isLinux) return;

    final names = cookieNames ?? const {'_t', '_forum_session', 'cf_clearance'};
    await strategy.syncCriticalFromController(controller, names, ctx, jar);
  }

  /// 从当前 WebView 控制器的实时 Cookie 中读取指定值
  Future<String?> readCookieValueFromController(
    InAppWebViewController controller,
    String name, {
    String? currentUrl,
  }) async {
    return strategy.readLiveCookieValue(
      controller,
      name,
      currentUrl: currentUrl,
    );
  }

  // ---------------------------------------------------------------------------
  // 私有辅助方法
  // ---------------------------------------------------------------------------

  /// Windows CDP 同步
  Future<void> _syncFromWebViewViaCDP(CookieSyncContext ctx) async {
    final controller = ctx.controller!;
    final resolvedCurrentUrl =
        ctx.currentUrl ?? (await controller.getUrl())?.toString();
    final cdpUrls = <String>{
      AppConstants.baseUrl,
      '${AppConstants.baseUrl}/',
      if (resolvedCurrentUrl != null && resolvedCurrentUrl.isNotEmpty)
        resolvedCurrentUrl,
      for (final host in ctx.relatedHosts) 'https://$host',
    }.toList();

    try {
      final result = await controller.callDevToolsProtocolMethod(
        methodName: 'Network.getCookies',
        parameters: {'urls': cdpUrls},
      );
      final rawCookies = result is Map<String, dynamic>
          ? result['cookies']
          : null;
      if (rawCookies is! List || rawCookies.isEmpty) {
        debugPrint(
          '[CookieJar][Windows] syncFromWebView(controller): no cookies',
        );
        return;
      }

      // 按 name|path 去重，优先 domain 版本
      final bestCookies = <String, Map<String, dynamic>>{};
      for (final raw in rawCookies.whereType<Map>()) {
        final name = raw['name']?.toString();
        final domain = raw['domain']?.toString() ?? '';
        if (name == null) continue;
        final normalized = domain.replaceFirst(RegExp(r'^\.'), '');
        if (normalized.isNotEmpty &&
            normalized != ctx.baseUri.host &&
            !normalized.endsWith('.${ctx.baseUri.host}') &&
            !ctx.baseUri.host.endsWith('.$normalized')) {
          continue;
        }
        final path = raw['path']?.toString() ?? '/';
        final key = '$name|$path';
        final existing = bestCookies[key];
        if (existing == null ||
            (!(existing['domain']?.toString().startsWith('.') ?? false) &&
                domain.startsWith('.'))) {
          bestCookies[key] = Map<String, dynamic>.from(
            raw.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }

      // 存入 CookieJar
      final bucketedCookies = <Uri, Map<String, io.Cookie>>{};
      for (final raw in bestCookies.values) {
        final name = raw['name'].toString();
        if (ctx.cookieNames != null && !ctx.cookieNames!.contains(name)) {
          continue;
        }
        final value = raw['value']?.toString() ?? '';
        final rawDomain = raw['domain']?.toString().trim();
        final isDomainCookie =
            rawDomain != null && rawDomain.startsWith('.');
        final normalizedDomain = rawDomain != null
            ? (rawDomain.startsWith('.')
                ? rawDomain.substring(1)
                : rawDomain)
            : null;

        io.Cookie cookie;
        try {
          cookie = io.Cookie(name, value);
        } catch (_) {
          cookie = io.Cookie(name, CookieValueCodec.encode(value));
        }
        cookie
          ..path = raw['path']?.toString() ?? '/'
          ..secure = raw['secure'] == true
          ..httpOnly = raw['httpOnly'] == true;

        if (isDomainCookie && normalizedDomain != null) {
          cookie.domain = '.$normalizedDomain';
        }

        final expiresRaw = raw['expires'];
        if (expiresRaw is num && expiresRaw > 0) {
          cookie.expires = DateTime.fromMillisecondsSinceEpoch(
            (expiresRaw * 1000).round(),
          );
        }

        if (cookie.expires != null &&
            cookie.expires!.isBefore(DateTime.now())) {
          continue;
        }
        if (cookie.value.isEmpty &&
            CookieJarService.isCriticalCookie(cookie.name)) {
          continue;
        }

        final hostForUri = normalizedDomain ?? ctx.baseUri.host;
        final bucketUri = Uri(scheme: ctx.baseUri.scheme, host: hostForUri);
        final dedupeKey =
            '${cookie.name}|${cookie.path}|${cookie.domain ?? hostForUri}';
        bucketedCookies.putIfAbsent(
          bucketUri,
          () => <String, io.Cookie>{},
        )[dedupeKey] = cookie;
      }

      // 先清掉关键 cookie 旧值
      final namesAboutToSync = <String>{};
      for (final cookies in bucketedCookies.values) {
        for (final cookie in cookies.values) {
          if (CookieJarService.isCriticalCookie(cookie.name)) {
            namesAboutToSync.add(cookie.name);
          }
        }
      }
      for (final name in namesAboutToSync) {
        await jar.deleteCookie(name);
      }

      var totalSynced = 0;
      for (final entry in bucketedCookies.entries) {
        final cookies = entry.value.values.toList();
        if (cookies.isEmpty) continue;
        await jar.cookieJar.saveFromResponse(entry.key, cookies);
        totalSynced += cookies.length;
      }

      // Bug #5 fix：写入后清理冲突副本
      await _cleanupConflictingCriticalCookies(namesAboutToSync, ctx);

      debugPrint(
        '[CookieJar][Windows] syncFromWebView(controller): $totalSynced cookies',
      );
      await CookieDiagnostics.logWindowsCookieSyncStatus(
        'syncFromWebView(controller)',
        jar: jar,
        ctx: ctx,
      );
    } catch (e) {
      debugPrint(
        '[CookieJar][Windows] syncFromWebView(controller) failed: $e',
      );
    }
  }

  /// Bug #5 fix：写入后检查关键 cookie，确保同名不存在 domain 类型冲突的副本
  Future<void> _cleanupConflictingCriticalCookies(
    Set<String> cookieNames,
    CookieSyncContext ctx,
  ) async {
    if (cookieNames.isEmpty) return;

    for (final name in cookieNames) {
      // 收集所有同名 cookie 副本
      final copies = <(io.Cookie, Uri)>[];
      for (final host in ctx.relatedHosts) {
        final hostUri = Uri.parse('https://$host');
        final cookies = await jar.cookieJar.loadForRequest(hostUri);
        for (final cookie in cookies) {
          if (cookie.name == name) {
            copies.add((cookie, hostUri));
          }
        }
      }

      if (copies.length <= 1) continue;

      // 按 domain 类型分组：domain cookie 和 host-only cookie
      final domainCopies =
          copies.where((c) => c.$1.domain != null).toList();
      final hostOnlyCopies =
          copies.where((c) => c.$1.domain == null).toList();

      // 两种类型都存在时，清除 host-only 副本（domain cookie 更权威）
      if (domainCopies.isNotEmpty && hostOnlyCopies.isNotEmpty) {
        final expired = DateTime.now().subtract(const Duration(days: 1));
        for (final (cookie, uri) in hostOnlyCopies) {
          final expiredCookie = io.Cookie(cookie.name, '')
            ..path = cookie.path ?? '/'
            ..expires = expired;
          await jar.cookieJar.saveFromResponse(uri, [expiredCookie]);
        }
        debugPrint(
          '[CookieJar] Cleaned ${hostOnlyCopies.length} conflicting '
          'host-only copies of $name',
        );
      }
    }
  }

  bool _shouldPersistWebViewDomainCookie({
    required String? rawDomain,
    required String? normalizedDomain,
    required Set<String> sourceHosts,
  }) {
    if (normalizedDomain == null) return false;
    if (rawDomain != null && rawDomain.trim().startsWith('.')) return true;
    for (final sourceHost in sourceHosts) {
      if (sourceHost != normalizedDomain &&
          sourceHost.endsWith('.$normalizedDomain')) {
        return true;
      }
    }
    return false;
  }

}
