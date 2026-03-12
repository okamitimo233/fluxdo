import 'package:dio/dio.dart';

import '../../../constants.dart';
import '../cookie/cookie_sync_service.dart';

/// 请求头拦截器
/// 负责设置 User-Agent 和 CSRF Token
class RequestHeaderInterceptor extends Interceptor {
  RequestHeaderInterceptor(this._cookieSync);

  final CookieSyncService _cookieSync;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 1. 设置 User-Agent
    options.headers['User-Agent'] = await AppConstants.getUserAgent();

    // 2. 注入 Client Hints 请求头（Sec-CH-UA 系列，仅移动端可用）
    final hints = AppConstants.clientHints;
    if (hints != null) {
      options.headers.addAll(hints);
    }

    // 3. 设置 CSRF Token（无数据时传 "undefined"）
    final skipCsrf = options.extra['skipCsrf'] == true;
    if (!skipCsrf) {
      final csrf = _cookieSync.csrfToken;
      options.headers['X-CSRF-Token'] = (csrf == null || csrf.isEmpty) ? 'undefined' : csrf;
    }

    // 4. API 请求（XHR）设置 Origin 和 Referer，文档类请求不设置
    if (options.headers['X-Requested-With'] == 'XMLHttpRequest') {
      options.headers['Origin'] = AppConstants.baseUrl;
      options.headers['Referer'] = '${AppConstants.baseUrl}/';
    }

    handler.next(options);
  }
}
