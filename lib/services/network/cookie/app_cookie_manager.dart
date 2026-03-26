import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../log/log_writer.dart';
import 'cookie_jar_service.dart';
import 'cookie_write_through.dart';

/// App-specific CookieManager.
/// Avoids saving Set-Cookie into redirect target domains by default.
class AppCookieManager extends Interceptor {
  AppCookieManager(
    this.cookieJar, {
    this.saveRedirectedCookies = false,
  });

  /// The cookie jar used to load and save cookies.
  final CookieJar cookieJar;

  /// Whether to also save Set-Cookie to redirect target domains when
  /// followRedirects is false. Default false to avoid cross-domain pollution.
  final bool saveRedirectedCookies;

  static final _setCookieReg = RegExp('(?<=)(,)(?=[^;]+?=)');

  /// Merge cookies into a Cookie string.
  /// Cookies with longer paths are listed before cookies with shorter paths.
  /// 同名 cookie 去重：优先保留 host-only cookie，避免重复发送。
  ///
  /// host-only cookie 来自服务器 Set-Cookie 响应（无 domain 属性），
  /// 代表服务器最新轮换的值（如 _t 会话 token）。
  /// domain cookie 来自 syncFromWebView（WKWebView 自动添加 domain），
  /// 可能是旧值。优先 host-only 确保发送服务器最新认可的值。
  static String _mergeCookies(List<Cookie> cookies) {
    cookies.sort((a, b) {
      if (a.path == null && b.path == null) {
        return 0;
      } else if (a.path == null) {
        return -1;
      } else if (b.path == null) {
        return 1;
      } else {
        return b.path!.length.compareTo(a.path!.length);
      }
    });
    // 按 name+path 去重，优先保留 host-only cookie（服务器最新值）
    final seen = <String>{};
    final deduped = <Cookie>[];
    // 先收集 host-only cookie（来自服务器直接 Set-Cookie 响应，是最新值）
    for (final cookie in cookies) {
      if (cookie.domain == null && seen.add('${cookie.name}|${cookie.path}')) {
        deduped.add(cookie);
      }
    }
    // 再收集没有 host-only 对应的 domain cookie（兜底）
    for (final cookie in cookies) {
      if (cookie.domain != null && seen.add('${cookie.name}|${cookie.path}')) {
        deduped.add(cookie);
      }
    }
    return deduped.map((cookie) => '${cookie.name}=${CookieValueCodec.decode(cookie.value)}').join('; ');
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final cookies = await loadCookies(options);
      options.headers[HttpHeaders.cookieHeader] =
          cookies.isNotEmpty ? cookies : null;
      handler.next(options);
    } catch (e, s) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: e,
          stackTrace: s,
          message: 'Failed to load cookies for the request.',
        ),
        true,
      );
    }
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      await saveCookies(response);
      handler.next(response);
    } catch (e, s) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.unknown,
          error: e,
          stackTrace: s,
          message: 'Failed to save cookies from the response.',
        ),
        true,
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response == null) {
      handler.next(err);
      return;
    }
    try {
      await saveCookies(response);
      handler.next(err);
    } catch (e, s) {
      handler.next(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.unknown,
          error: e,
          stackTrace: s,
          message: 'Failed to save cookies from the error response.',
        ),
      );
    }
  }

  /// Load cookies in cookie string for the request.
  Future<String> loadCookies(RequestOptions options) async {
    final savedCookies = await cookieJar.loadForRequest(options.uri);
    final previousCookies =
        options.headers[HttpHeaders.cookieHeader] as String?;
    final allCookies = [
      ...?previousCookies
          ?.split(';')
          .where((e) => e.isNotEmpty)
          .map((c) => Cookie.fromSetCookieValue(c)),
      ...savedCookies,
    ];

    // 诊断：记录 _t cookie 的 host-only/domain 变体
    final tCookies = allCookies.where((c) => c.name == '_t').toList();
    if (tCookies.length > 1) {
      final hostOnly = tCookies.where((c) => c.domain == null).map((c) => c.value.length);
      final domain = tCookies.where((c) => c.domain != null).map((c) => '${c.domain}:${c.value.length}');
      debugPrint('[CookieManager] _t 多副本: hostOnly=$hostOnly, domain=$domain, '
          'uri=${options.uri.host}${options.uri.path}');
    }

    final cookies = _mergeCookies(allCookies);
    return cookies;
  }

  /// Save cookies from the response including redirected requests.
  Future<void> saveCookies(Response response) async {
    final setCookies = response.headers[HttpHeaders.setCookieHeader];
    if (setCookies == null || setCookies.isEmpty) {
      return;
    }

    final List<Cookie> cookies = setCookies
        .map((str) => str.split(_setCookieReg))
        .expand((cookie) => cookie)
        .where((cookie) => cookie.isNotEmpty)
        .map((str) => Cookie.fromSetCookieValue(str))
        .toList();

    // 拦截服务端对关键 cookie 的删除指令。
    // 服务端可能在 200 响应中通过 Set-Cookie 删除 _t（设置为过期/空值），
    // 如果无条件写入 CookieJar，会导致验证机制还没判断完 _t 就已经丢了。
    // 只过滤「删除」操作，正常的「更新」（有值且未过期）仍然放行。
    final filteredCookies = <Cookie>[];
    for (final cookie in cookies) {
      final isSessionCookie = cookie.name == '_t' || cookie.name == '_forum_session';
      if (isSessionCookie) {
        final isExpired = cookie.expires != null &&
            cookie.expires!.isBefore(DateTime.now());
        final isDeletion =
            cookie.value == 'del' || cookie.value.isEmpty || isExpired;
        final uri = response.requestOptions.uri;
        debugPrint('[CookieManager] _t ${isDeletion ? "DEL(blocked)" : "SET"} '
            'from ${response.requestOptions.method} ${uri.host}${uri.path} '
            '(status=${response.statusCode}, len=${cookie.value.length}, '
            'domain=${cookie.domain}, hasLoggedIn=${response.requestOptions.headers['Discourse-Logged-In']})');
        LogWriter.instance.write({
          'timestamp': DateTime.now().toIso8601String(),
          'level': isDeletion ? 'warning' : 'info',
          'type': 'cookie_change',
          'event': isDeletion ? 'token_cookie_delete_blocked' : 'token_cookie_updated',
          'message': isDeletion ? '${cookie.name} 删除被拦截' : '${cookie.name} cookie 被更新',
          'valueLength': cookie.value.length,
          'isExpired': isExpired,
          'method': response.requestOptions.method,
          'url': uri.path,
          'fullUrl': uri.toString(),
          'statusCode': response.statusCode,
          'cookieDomain': cookie.domain,
          'hasLoggedInHeader': response.requestOptions.headers['Discourse-Logged-In'] == 'true',
        });
        if (isDeletion) {
          // 不写入 CookieJar，由业务层（_handleAuthInvalid）决定是否真正清除
          continue;
        }
      }
      filteredCookies.add(cookie);
    }

    // Save cookies for the original site.
    final originalUri = response.requestOptions.uri;
    await cookieJar.saveFromResponse(
      originalUri.resolveUri(response.realUri),
      filteredCookies,
    );

    // 实时推送关键 cookie 到 WebView（不阻塞 Dio 响应链）
    unawaited(CookieWriteThrough.instance.writeThrough(
      filteredCookies,
      originalUri,
    ));

    // Optionally save cookies for redirected locations.
    final allowRedirectSave = response.requestOptions.extra['allowRedirectSetCookie'] == true;
    if (!(saveRedirectedCookies || allowRedirectSave)) {
      return;
    }

    final statusCode = response.statusCode ?? 0;
    final locations = response.headers[HttpHeaders.locationHeader] ?? [];
    final redirected = statusCode >= 300 && statusCode < 400;
    if (redirected && locations.isNotEmpty) {
      final baseUri = response.realUri;
      await Future.wait(
        locations.map(
          (location) => cookieJar.saveFromResponse(
            baseUri.resolve(location),
            cookies,
          ),
        ),
      );
    }
  }
}
