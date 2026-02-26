import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import 'cookie_jar_service.dart';

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
  /// 同名 cookie 去重：优先保留 domain cookie，避免重复发送。
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
    // 按 name+path 去重，优先保留 domain cookie
    final seen = <String>{};
    final deduped = <Cookie>[];
    // 先收集 domain cookie
    for (final cookie in cookies) {
      if (cookie.domain != null && seen.add('${cookie.name}|${cookie.path}')) {
        deduped.add(cookie);
      }
    }
    // 再收集没有 domain cookie 对应的 host-only cookie
    for (final cookie in cookies) {
      if (cookie.domain == null && seen.add('${cookie.name}|${cookie.path}')) {
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
    final cookies = _mergeCookies([
      ...?previousCookies
          ?.split(';')
          .where((e) => e.isNotEmpty)
          .map((c) => Cookie.fromSetCookieValue(c)),
      ...savedCookies,
    ]);
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
        .map((str) {
          final cookie = Cookie.fromSetCookieValue(str);
          // Dart SDK 解析 Set-Cookie 时不对 Domain 属性做规范化，
          // 但 RFC 6265 §5.2.3 规定 Domain=linux.do 等价于 Domain=.linux.do，
          // 都是域级 cookie（匹配自身及所有子域）。
          // 补上前导点以对齐 WKWebView 的 HTTPCookie 行为。
          if (cookie.domain != null && !cookie.domain!.startsWith('.')) {
            cookie.domain = '.${cookie.domain}';
          }
          return cookie;
        })
        .toList();

    // Save cookies for the original site.
    final originalUri = response.requestOptions.uri;
    final realUri = originalUri.resolveUri(response.realUri);
    await cookieJar.saveFromResponse(realUri, cookies);

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
