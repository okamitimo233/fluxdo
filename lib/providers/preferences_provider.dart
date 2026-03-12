import 'dart:io';

import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';

class AppPreferences {
  final bool autoPanguSpacing;
  /// 阅读时自动优化中英文混排间距
  final bool displayPanguSpacing;
  final bool anonymousShare;
  final bool longPressPreview;
  final bool openExternalLinksInAppBrowser;
  /// 内容字体缩放比例，范围 0.8 ~ 1.4，默认 1.0
  final double contentFontScale;
  /// 分享图片主题索引
  final int shareImageThemeIndex;
  /// 自动填充登录凭证
  final bool autoFillLogin;
  /// 崩溃日志上报（仅 Android）
  final bool crashlytics;
  /// 竖屏锁定
  final bool portraitLock;
  /// 滚动时收起顶栏和底栏
  final bool hideBarOnScroll;
  /// 退出时清除图片缓存
  final bool clearCacheOnExit;

  const AppPreferences({
    required this.autoPanguSpacing,
    required this.displayPanguSpacing,
    required this.anonymousShare,
    required this.longPressPreview,
    required this.openExternalLinksInAppBrowser,
    required this.contentFontScale,
    required this.shareImageThemeIndex,
    required this.autoFillLogin,
    required this.crashlytics,
    required this.portraitLock,
    required this.hideBarOnScroll,
    required this.clearCacheOnExit,
  });

  AppPreferences copyWith({
    bool? autoPanguSpacing,
    bool? displayPanguSpacing,
    bool? anonymousShare,
    bool? longPressPreview,
    bool? openExternalLinksInAppBrowser,
    double? contentFontScale,
    int? shareImageThemeIndex,
    bool? autoFillLogin,
    bool? crashlytics,
    bool? portraitLock,
    bool? hideBarOnScroll,
    bool? clearCacheOnExit,
  }) {
    return AppPreferences(
      autoPanguSpacing: autoPanguSpacing ?? this.autoPanguSpacing,
      displayPanguSpacing: displayPanguSpacing ?? this.displayPanguSpacing,
      anonymousShare: anonymousShare ?? this.anonymousShare,
      longPressPreview: longPressPreview ?? this.longPressPreview,
      openExternalLinksInAppBrowser:
          openExternalLinksInAppBrowser ?? this.openExternalLinksInAppBrowser,
      contentFontScale: contentFontScale ?? this.contentFontScale,
      shareImageThemeIndex: shareImageThemeIndex ?? this.shareImageThemeIndex,
      autoFillLogin: autoFillLogin ?? this.autoFillLogin,
      crashlytics: crashlytics ?? this.crashlytics,
      portraitLock: portraitLock ?? this.portraitLock,
      hideBarOnScroll: hideBarOnScroll ?? this.hideBarOnScroll,
      clearCacheOnExit: clearCacheOnExit ?? this.clearCacheOnExit,
    );
  }
}

class PreferencesNotifier extends StateNotifier<AppPreferences> {
  static const String _autoPanguSpacingKey = 'pref_auto_pangu_spacing';
  static const String _displayPanguSpacingKey = 'pref_display_pangu_spacing';
  static const String _anonymousShareKey = 'pref_anonymous_share';
  static const String _longPressPreviewKey = 'pref_long_press_preview';
  static const String _openExternalLinksInAppBrowserKey =
      'pref_open_external_links_in_app_browser';
  static const String _contentFontScaleKey = 'pref_content_font_scale';
  static const String _shareImageThemeIndexKey = 'pref_share_image_theme_index';
  static const String _autoFillLoginKey = 'pref_auto_fill_login';
  static const String _crashlyticsKey = 'pref_crashlytics';
  static const String _portraitLockKey = 'pref_portrait_lock';
  static const String _hideBarOnScrollKey = 'pref_hide_bar_on_scroll';
  static const String _clearCacheOnExitKey = 'pref_clear_cache_on_exit';

  static const _crashlyticsChannel =
      MethodChannel('com.github.lingyan000.fluxdo/crashlytics');

  PreferencesNotifier(this._prefs)
      : super(
          AppPreferences(
            autoPanguSpacing: _prefs.getBool(_autoPanguSpacingKey) ?? false,
            displayPanguSpacing: _prefs.getBool(_displayPanguSpacingKey) ?? false,
            anonymousShare: _prefs.getBool(_anonymousShareKey) ?? false,
            longPressPreview: _prefs.getBool(_longPressPreviewKey) ?? true,
            openExternalLinksInAppBrowser:
                _prefs.getBool(_openExternalLinksInAppBrowserKey) ?? false,
            contentFontScale: _prefs.getDouble(_contentFontScaleKey) ?? 1.0,
            shareImageThemeIndex: _prefs.getInt(_shareImageThemeIndexKey) ?? 0,
            autoFillLogin: _prefs.getBool(_autoFillLoginKey) ?? true,
            crashlytics: _prefs.getBool(_crashlyticsKey) ?? false,
            portraitLock: _prefs.getBool(_portraitLockKey) ?? false,
            hideBarOnScroll: _prefs.getBool(_hideBarOnScrollKey) ?? true,
            clearCacheOnExit: _prefs.getBool(_clearCacheOnExitKey) ?? false,
          ),
        ) {
    isPortraitLocked = state.portraitLock;
  }

  final SharedPreferences _prefs;

  Future<void> setAutoPanguSpacing(bool enabled) async {
    state = state.copyWith(autoPanguSpacing: enabled);
    await _prefs.setBool(_autoPanguSpacingKey, enabled);
  }

  Future<void> setDisplayPanguSpacing(bool enabled) async {
    state = state.copyWith(displayPanguSpacing: enabled);
    await _prefs.setBool(_displayPanguSpacingKey, enabled);
  }

  Future<void> setAnonymousShare(bool enabled) async {
    state = state.copyWith(anonymousShare: enabled);
    await _prefs.setBool(_anonymousShareKey, enabled);
  }

  Future<void> setLongPressPreview(bool enabled) async {
    state = state.copyWith(longPressPreview: enabled);
    await _prefs.setBool(_longPressPreviewKey, enabled);
  }

  Future<void> setOpenExternalLinksInAppBrowser(bool enabled) async {
    state = state.copyWith(openExternalLinksInAppBrowser: enabled);
    await _prefs.setBool(_openExternalLinksInAppBrowserKey, enabled);
  }

  Future<void> setContentFontScale(double scale) async {
    // 限制范围在 0.8 ~ 1.4
    final clampedScale = scale.clamp(0.8, 1.4);
    state = state.copyWith(contentFontScale: clampedScale);
    await _prefs.setDouble(_contentFontScaleKey, clampedScale);
  }

  Future<void> setShareImageThemeIndex(int index) async {
    state = state.copyWith(shareImageThemeIndex: index);
    await _prefs.setInt(_shareImageThemeIndexKey, index);
  }

  Future<void> setAutoFillLogin(bool enabled) async {
    state = state.copyWith(autoFillLogin: enabled);
    await _prefs.setBool(_autoFillLoginKey, enabled);
  }

  Future<void> setCrashlytics(bool enabled) async {
    state = state.copyWith(crashlytics: enabled);
    await _prefs.setBool(_crashlyticsKey, enabled);
    if (Platform.isAndroid) {
      await _crashlyticsChannel.invokeMethod(
        'setCrashlyticsEnabled',
        {'enabled': enabled},
      );
    }
  }

  Future<void> setPortraitLock(bool enabled) async {
    state = state.copyWith(portraitLock: enabled);
    await _prefs.setBool(_portraitLockKey, enabled);
    isPortraitLocked = enabled;
    if (enabled) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  Future<void> setHideBarOnScroll(bool enabled) async {
    state = state.copyWith(hideBarOnScroll: enabled);
    await _prefs.setBool(_hideBarOnScrollKey, enabled);
  }

  Future<void> setClearCacheOnExit(bool enabled) async {
    state = state.copyWith(clearCacheOnExit: enabled);
    await _prefs.setBool(_clearCacheOnExitKey, enabled);
  }

  /// 当前竖屏锁定状态（供视频播放器等无法访问 ref 的组件使用）
  static bool isPortraitLocked = false;

  /// 恢复方向锁定设置
  /// 视频退出全屏后调用，重新应用竖屏锁定
  static Future<void> restoreOrientationLock() async {
    if (isPortraitLocked) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }
}

final preferencesProvider =
    StateNotifierProvider<PreferencesNotifier, AppPreferences>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PreferencesNotifier(prefs);
});
