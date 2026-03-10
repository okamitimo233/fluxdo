part of 'discourse_service.dart';

/// 认证相关
mixin _AuthMixin on _DiscourseServiceBase {
  /// 初始化拦截器
  void _initInterceptors() {
    // 设置 PreloadedDataService 的登录失效回调
    PreloadedDataService().setAuthInvalidCallback(() {
      _handleAuthInvalid(
        '登录已失效，请重新登录',
        source: 'preloaded_data',
        triggerInfo: '有 token 但没有 currentUser，WebView 验证确认已登出',
      );
    });

    // 添加业务特定拦截器
    _dio.interceptors.insert(0, InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (!_credentialsLoaded) {
          await _loadStoredCredentials();
          _credentialsLoaded = true;
        }

        if (_tToken != null && _tToken!.isNotEmpty) {
          options.headers['Discourse-Logged-In'] = 'true';
          options.headers['Discourse-Present'] = 'true';
        }

        debugPrint('[DIO] ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) async {
        final skipAuthCheck = response.requestOptions.extra['skipAuthCheck'] == true;

        final loggedOut = response.headers.value('discourse-logged-out');
        if (!skipAuthCheck && loggedOut != null && loggedOut.isNotEmpty && !_isLoggingOut) {
          final jarTToken = await _cookieJar.getTToken();
          await AuthLogService().logAuthInvalid(
            source: 'response_header',
            reason: 'discourse-logged-out',
            extra: {
              'method': response.requestOptions.method,
              'url': response.requestOptions.uri.toString(),
              'statusCode': response.statusCode,
              'responseHeaders': response.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
              'jarHasToken': jarTToken != null && jarTToken.isNotEmpty,
              'jarTokenLength': jarTToken?.length,
              'memHasToken': _tToken != null && _tToken!.isNotEmpty,
            },
          );
          await _handleAuthInvalid(
            '登录已失效，请重新登录',
            source: 'response_header',
            triggerInfo: '${response.requestOptions.method} ${response.requestOptions.uri} → ${response.statusCode}',
          );
          return handler.next(response);
        }

        final tToken = await _cookieJar.getTToken();
        if (tToken != null && tToken.isNotEmpty) {
          _tToken = tToken;
        }

        final username = response.headers.value('x-discourse-username');
        if (username != null && username.isNotEmpty && username != _username) {
          _username = username;
          _storage.write(key: DiscourseService._usernameKey, value: username);
        }

        debugPrint('[DIO] ${response.statusCode} ${response.requestOptions.uri}');
        handler.next(response);
      },
      onError: (error, handler) async {
        final skipAuthCheck = error.requestOptions.extra['skipAuthCheck'] == true;
        final data = error.response?.data;
        debugPrint('[DIO] Error: ${error.response?.statusCode}');

        final loggedOut = error.response?.headers.value('discourse-logged-out');
        if (!skipAuthCheck && loggedOut != null && loggedOut.isNotEmpty && !_isLoggingOut) {
          final jarTToken = await _cookieJar.getTToken();
          await AuthLogService().logAuthInvalid(
            source: 'error_response_header',
            reason: 'discourse-logged-out',
            extra: {
              'method': error.requestOptions.method,
              'url': error.requestOptions.uri.toString(),
              'statusCode': error.response?.statusCode,
              'responseHeaders': error.response?.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
              'errorMessage': error.message,
              'jarHasToken': jarTToken != null && jarTToken.isNotEmpty,
              'jarTokenLength': jarTToken?.length,
              'memHasToken': _tToken != null && _tToken!.isNotEmpty,
            },
          );
          await _handleAuthInvalid(
            '登录已失效，请重新登录',
            source: 'error_response_header',
            triggerInfo: '${error.requestOptions.method} ${error.requestOptions.uri} → ${error.response?.statusCode}',
          );
          return handler.next(error);
        }

        if (!skipAuthCheck && data is Map && data['error_type'] == 'not_logged_in') {
          final jarTToken = await _cookieJar.getTToken();
          await AuthLogService().logAuthInvalid(
            source: 'error_response',
            reason: data['error_type']?.toString() ?? 'not_logged_in',
            extra: {
              'method': error.requestOptions.method,
              'url': error.requestOptions.uri.toString(),
              'statusCode': error.response?.statusCode,
              'errors': data['errors'],
              'responseHeaders': error.response?.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
              'errorMessage': error.message,
              'jarHasToken': jarTToken != null && jarTToken.isNotEmpty,
              'jarTokenLength': jarTToken?.length,
              'memHasToken': _tToken != null && _tToken!.isNotEmpty,
            },
          );
          final message = (data['errors'] as List?)?.first?.toString() ?? '登录已失效，请重新登录';
          await _handleAuthInvalid(
            message,
            source: 'error_response_body',
            triggerInfo: '${error.requestOptions.method} ${error.requestOptions.uri} → ${error.response?.statusCode}, error_type=${data['error_type']}',
          );
        }

        handler.next(error);
      },
    ));
  }

  /// 设置导航 context
  void setNavigatorContext(BuildContext context) {
    _cfChallenge.setContext(context);
  }

  Future<void> _handleAuthInvalid(
    String message, {
    String? source,
    String? triggerInfo,
  }) async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    // 记录被动退出日志（含触发来源，方便排查）
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'warning',
      'type': 'lifecycle',
      'event': 'logout_passive',
      'message': '登录失效被动退出',
      'reason': message,
      if (source != null) 'source': source,
      if (triggerInfo != null) 'trigger': triggerInfo,
    });

    await logout(callApi: false, refreshPreload: true);
    _isLoggingOut = false;
    _authErrorController.add(message);
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    final tToken = await _cookieJar.getTToken();
    if (tToken == null || tToken.isEmpty) return false;
    _tToken = tToken;
    _username = await _storage.read(key: DiscourseService._usernameKey);
    return true;
  }

  /// 仅设置 token，不触发状态广播（登录流程中先设置 token，等数据就绪后再广播）
  void setToken(String tToken) {
    _tToken = tToken;
    _credentialsLoaded = false;
  }

  /// 登录成功后通知监听者（应在预加载数据就绪后调用）
  /// Cookie 写入由 syncFromWebView() 统一处理。
  void onLoginSuccess(String tToken) {
    _tToken = tToken;
    _credentialsLoaded = false;
    _authStateController.add(null);
  }

  /// 保存用户名
  Future<void> saveUsername(String username) async {
    _username = username;
    await _storage.write(key: DiscourseService._usernameKey, value: username);
  }

  /// 登出
  Future<void> logout({bool callApi = true, bool refreshPreload = true}) async {
    // ===== 第一步：切断所有旧请求 =====
    AuthSession().advance();

    // ===== 第二步：主动停止后台 Service =====
    MessageBusService().stopAll();
    CfClearanceRefreshService().stop();

    // ===== 第三步：调用登出 API（可选，用新的 generation） =====
    if (callApi) {
      final usernameForLogout = _username ?? await _storage.read(key: DiscourseService._usernameKey);
      try {
        if (usernameForLogout != null && usernameForLogout.isNotEmpty) {
          await _dio.delete('/session/$usernameForLogout');
        }
      } catch (e) {
        debugPrint('[DiscourseService] Logout API failed: $e');
      }
    }

    // ===== 第四步：清除内存状态 =====
    _tToken = null;
    _username = null;
    _cachedUserSummary = null;
    _cachedUserSummaryUsername = null;
    _userSummaryCacheTime = null;
    await _storage.delete(key: DiscourseService._usernameKey);
    _credentialsLoaded = false;

    // ===== 第五步：清除 Cookie（保留 cf_clearance）=====
    await _cookieSync.reset();
    final cfClearanceCookie = await _cookieJar.getCfClearanceCookie();
    await _cookieJar.clearAll();
    if (cfClearanceCookie != null) {
      await _cookieJar.restoreCfClearance(cfClearanceCookie);
    }

    // ===== 第六步：刷新预加载数据（确保新状态就绪后再广播）=====
    PreloadedDataService().reset();
    if (refreshPreload) {
      await PreloadedDataService().refresh();
    }

    // ===== 第七步：广播状态变更（此时一切已就绪）=====
    currentUserNotifier.value = null;
    _authStateController.add(null);
  }
}
