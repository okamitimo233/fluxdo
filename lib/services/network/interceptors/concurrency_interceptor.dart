import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';

/// 全局并发限制拦截器
///
/// 控制同时在飞的 HTTP 请求数量，超出上限的请求自动排队等待。
/// 避免 AppStateRefresher 等场景一次性打出过多请求触发服务端 429。
class ConcurrencyInterceptor extends Interceptor {
  final int maxConcurrent;
  int _running = 0;
  final _queue = Queue<Completer<void>>();

  ConcurrencyInterceptor({this.maxConcurrent = 6});

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 已达上限，排队等待
    if (_running >= maxConcurrent) {
      final completer = Completer<void>();
      _queue.add(completer);
      await completer.future;
    }
    _running++;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _release();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _release();
    handler.next(err);
  }

  void _release() {
    _running--;
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    }
  }
}
