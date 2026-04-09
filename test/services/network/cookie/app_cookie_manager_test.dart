import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/cookie/app_cookie_manager.dart';

void main() {
  group('AppCookieManager.loadCookies', () {
    test('忽略 RequestOptions 上残留的旧 Cookie 头，始终使用 CookieJar 最新值', () async {
      final jar = CookieJar();
      final uri = Uri.parse('https://linux.do/session/csrf');
      await jar.saveFromResponse(uri, [
        Cookie('_t', 'new-token')..path = '/',
      ]);

      final manager = AppCookieManager(jar);
      final options = RequestOptions(
        path: '/session/csrf',
        baseUrl: 'https://linux.do',
        method: 'GET',
        headers: {
          HttpHeaders.cookieHeader: '_t=old-token; other=legacy',
        },
      );

      final cookieHeader = await manager.loadCookies(options);

      expect(cookieHeader, '_t=new-token');
      expect(cookieHeader, isNot(contains('old-token')));
      expect(cookieHeader, isNot(contains('other=legacy')));
    });
  });
}
