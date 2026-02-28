import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ldc_user_info.dart';
import '../services/ldc_oauth_service.dart';
import '../services/network/exceptions/oauth_exception.dart';
import 'core_providers.dart';

final ldcUserInfoProvider = AsyncNotifierProvider<LdcUserInfoNotifier, LdcUserInfo?>(() {
  return LdcUserInfoNotifier();
});

class LdcUserInfoNotifier extends AsyncNotifier<LdcUserInfo?> {
  static const String _cacheKey = 'ldc_user_info';
  static const String _ldcEnabledKey = 'ldc_enabled';
  static const String _cacheUserKey = 'ldc_user_info_username';

  @override
  Future<LdcUserInfo?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = await ref.watch(currentUserProvider.future);
    if (currentUser == null) {
      await _clearCache(prefs);
      return null;
    }
    final enabled = prefs.getBool(_ldcEnabledKey) ?? false;

    if (!enabled) return null;

    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      try {
        final cachedUser = prefs.getString(_cacheUserKey);
        if (cachedUser != null && cachedUser != currentUser.username) {
          await _clearCache(prefs);
          return await _fetchUserInfo();
        }
        final json = jsonDecode(cached) as Map<String, dynamic>;
        final cachedInfo = LdcUserInfo.fromJson(json);
        refresh();
        return cachedInfo;
      } catch (e) {
        // 缓存损坏，继续刷新
      }
    }

    return await _fetchUserInfo();
  }

  Future<LdcUserInfo?> _fetchUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_ldcEnabledKey) ?? false;

    if (!enabled) return null;

    final currentUser = await ref.read(currentUserProvider.future);
    if (currentUser == null) return null;
    final gamificationScore = currentUser.gamificationScore;

    final service = LdcOAuthService();
    final userInfo = await service.getUserInfo(gamificationScore: gamificationScore);

    if (userInfo != null) {
      await prefs.setString(_cacheKey, jsonEncode(userInfo.toJson()));
      await prefs.setString(_cacheUserKey, userInfo.username);
    }

    return userInfo;
  }

  Future<void> refresh() async {
    final previousData = state.value;
    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<LdcUserInfo?>().copyWithPrevious(state);
    try {
      final result = await _fetchUserInfo();
      state = AsyncValue.data(result);
    } catch (e, st) {
      if (e is OAuthExpiredException) {
        // 登录态过期：清除缓存并立即反映到 UI
        final prefs = await SharedPreferences.getInstance();
        await _clearCache(prefs);
        state = AsyncValue.error(e, st);
      } else if (previousData != null) {
        // 网络错误等：保留旧数据
        state = AsyncValue.data(previousData);
      } else {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearCache(prefs);
    state = const AsyncValue.data(null);
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ldcEnabledKey, false);
    await _clearCache(prefs);
    state = const AsyncValue.data(null);
  }

  Future<void> _clearCache(SharedPreferences prefs) async {
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheUserKey);
  }
}
