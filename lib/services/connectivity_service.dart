import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'network/discourse_dio.dart';

/// 网络连通性检测服务
///
/// 参考 Discourse `NetworkConnectivity` 服务：
/// - 监听设备网络状态变化（WiFi/移动数据断开/恢复）
/// - 通过 ping `/srv/status` 验证服务器可达性
/// - 断开时定时重试，恢复后通知订阅者
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;

  bool _isConnected = true;
  bool _initialized = false;
  final _controller = StreamController<bool>.broadcast();

  /// 连接状态流（true = 已连接，false = 已断开）
  Stream<bool> get connectionStream => _controller.stream;

  /// 当前是否已连接
  bool get isConnected => _isConnected;

  /// 使用项目统一 Dio（含平台适配器、Cookie 等），
  /// 但关闭重试、CF 验证、并发限制，避免 ping 请求被干扰或排队
  late final Dio _pingDio = DiscourseDio.create(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    maxConcurrent: null,
    enableRetry: false,
    enableCfChallenge: false,
  );

  /// 初始化服务
  void init() {
    if (_initialized) return;
    _initialized = true;

    // 监听网络变化事件
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // 启动时检查一次
    _checkInitial();
  }

  Future<void> _checkInitial() async {
    try {
      final result = await _connectivity.checkConnectivity();
      await _onConnectivityChanged(result);
    } catch (e) {
      debugPrint('[Connectivity] 初始检查失败: $e');
    }
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final hasNetwork = results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);

    if (!hasNetwork) {
      // 设备无网络连接
      _setConnected(false);
      return;
    }

    // 有网络连接，ping 服务器验证可达性
    final reachable = await pingServer();
    _setConnected(reachable);
  }

  /// ping 服务器验证可达性
  /// 返回 true 表示服务器可达
  ///
  /// 判断逻辑：只要收到任何 HTTP 响应（包括 CF 403）就算可达，
  /// 只有网络层异常（超时、DNS 失败、连接被拒）才算不可达。
  Future<bool> pingServer() async {
    try {
      await _pingDio.get(
        '/srv/status',
        options: Options(
          // 接受任意状态码，不抛异常——CF 403 也算服务器可达
          validateStatus: (_) => true,
        ),
      );
      return true;
    } on DioException catch (e) {
      // 收到了 HTTP 响应但 Dio 仍然抛了异常（如重定向等），视为可达
      if (e.response != null) return true;
      debugPrint('[Connectivity] ping 失败: ${e.type}');
      return false;
    } catch (e) {
      debugPrint('[Connectivity] ping 异常: $e');
      return false;
    }
  }

  void _setConnected(bool connected) {
    if (_isConnected == connected) return;
    _isConnected = connected;
    _controller.add(connected);
    debugPrint('[Connectivity] 连接状态变更: ${connected ? "已连接" : "已断开"}');

    if (!connected) {
      _startRetry();
    } else {
      _stopRetry();
    }
  }

  /// 断开时每 5 秒重试
  void _startRetry() {
    _stopRetry();
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final reachable = await pingServer();
      if (reachable) {
        _setConnected(true);
      }
    });
  }

  void _stopRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// 手动触发一次检查（如 App 回到前台时）
  Future<void> check() async {
    final reachable = await pingServer();
    _setConnected(reachable);
  }

  void dispose() {
    _connectivitySub?.cancel();
    _stopRetry();
    _controller.close();
    _initialized = false;
  }
}
