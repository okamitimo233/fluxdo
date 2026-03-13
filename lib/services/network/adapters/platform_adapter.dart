import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import '../doh/network_settings_service.dart';
import '../proxy/proxy_settings_service.dart';
import 'cronet_fallback_service.dart';
import 'network_http_adapter.dart';
import 'webview_http_adapter.dart';

/// 当前使用的适配器类型
enum AdapterType {
  webview, // WebView 适配器（Windows）
  native, // Native 适配器（Cronet/Cupertino）
  network, // Network 适配器（通过代理）
}

/// 全局变量：记录当前使用的适配器类型
AdapterType? _currentAdapterType;

/// 获取当前使用的适配器类型
AdapterType? getCurrentAdapterType() => _currentAdapterType;

/// 获取适配器类型的显示名称
String getAdapterDisplayName(AdapterType type) {
  switch (type) {
    case AdapterType.webview:
      return 'WebView 适配器';
    case AdapterType.native:
      return Platform.isAndroid ? 'Cronet 适配器' : 'Cupertino 适配器';
    case AdapterType.network:
      return 'Network 适配器';
  }
}

/// 配置平台适配器
void configurePlatformAdapter(Dio dio) {
  final settings = NetworkSettingsService.instance;
  final proxySettings = ProxySettingsService.instance;
  final fallbackService = CronetFallbackService.instance;

  if (Platform.isWindows) {
    // Windows: 始终使用 WebView 适配器
    _configureWebViewAdapter(dio);
    _currentAdapterType = AdapterType.webview;
  } else {
    // Android / iOS / macOS / Linux: 动态适配器，请求时自动切换
    dio.httpClientAdapter = _DynamicAdapter(
      settings,
      proxySettings,
      fallbackService,
    );
    _currentAdapterType = _resolveAdapterType(settings, proxySettings, fallbackService);
  }
}

/// 配置 WebView 适配器
void _configureWebViewAdapter(Dio dio) {
  final adapter = WebViewHttpAdapter();
  dio.httpClientAdapter = adapter;
  adapter.initialize().then((_) {
    debugPrint('[DIO] Using WebViewHttpAdapter on Windows');
  }).catchError((e) {
    debugPrint('[DIO] WebViewHttpAdapter init failed: $e');
  });
}

AdapterType _resolveAdapterType(
  NetworkSettingsService settings,
  ProxySettingsService proxySettings,
  CronetFallbackService fallbackService,
) {
  // 代理或 DOH 启用时使用 NetworkHttpAdapter（通过本地 Rust 网关转发）
  if (settings.shouldRunLocalProxy || fallbackService.hasFallenBack) {
    return AdapterType.network;
  }
  return AdapterType.native;
}

/// 创建当前平台对应的 NativeAdapter
HttpClientAdapter _createNativeAdapter() {
  if (kDebugMode && (Platform.isMacOS || Platform.isIOS)) {
    // 调试模式下使用默认适配器（IOHttpClientAdapter），避免 NativeAdapter 热重启崩溃
    debugPrint('[DIO] Dynamic adapter -> IOHttpClientAdapter (debug mode)');
    return IOHttpClientAdapter();
  }
  if (Platform.isIOS || Platform.isMacOS) {
    // Release 模式: URLSession 默认会自动管理 Cookie（httpShouldSetCookies=true），
    // 会与 AppCookieManager 拦截器冲突。禁用 URLSession 的 Cookie 自动管理。
    final config = URLSessionConfiguration.ephemeralSessionConfiguration();
    config.httpShouldSetCookies = false;
    return NativeAdapter(createCupertinoConfiguration: () => config);
  }
  return NativeAdapter();
}

/// 动态适配器：每次请求时根据设置 version 变化自动切换底层适配器
///
/// Android 上在 network ↔ native（Cronet）之间切换；
/// iOS/macOS/Linux 上在 network ↔ native（Cupertino/IO）之间切换。
/// 解决了非 Android 平台切换 DOH/代理后必须重启的问题。
class _DynamicAdapter implements HttpClientAdapter {
  _DynamicAdapter(this._settings, this._proxySettings, this._fallbackService);

  final NetworkSettingsService _settings;
  final ProxySettingsService _proxySettings;
  final CronetFallbackService _fallbackService;

  HttpClientAdapter? _delegate;
  AdapterType? _delegateType;
  int _settingsVersion = -1;
  int _proxyVersion = -1;
  bool _hasFallenBack = false;
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (_closed) {
      throw StateError("Can't establish connection after the adapter was closed.");
    }
    final delegate = _ensureDelegate();
    return delegate.fetch(options, requestStream, cancelFuture);
  }

  HttpClientAdapter _ensureDelegate() {
    final desiredType = _resolveAdapterType(
      _settings,
      _proxySettings,
      _fallbackService,
    );
    final settingsVersion = _settings.version;
    final proxyVersion = _proxySettings.version;
    final hasFallenBack = _fallbackService.hasFallenBack;

    final shouldRebuild = _delegate == null ||
        _delegateType != desiredType ||
        _settingsVersion != settingsVersion ||
        _proxyVersion != proxyVersion ||
        _hasFallenBack != hasFallenBack;

    if (!shouldRebuild) {
      return _delegate!;
    }

    _delegate?.close(force: true);
    if (desiredType == AdapterType.network) {
      _delegate = NetworkHttpAdapter(_settings, _proxySettings);
      debugPrint('[DIO] Dynamic adapter -> NetworkHttpAdapter');
    } else {
      _delegate = _createNativeAdapter();
      debugPrint('[DIO] Dynamic adapter -> NativeAdapter');
    }

    _delegateType = desiredType;
    _settingsVersion = settingsVersion;
    _proxyVersion = proxyVersion;
    _hasFallenBack = hasFallenBack;
    _currentAdapterType = desiredType;
    return _delegate!;
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    _delegate?.close(force: force);
  }
}
