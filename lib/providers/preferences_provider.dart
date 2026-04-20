import 'dart:io';

import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../navigation/nav_action_bus.dart';
import '../services/network/request_scheduler_config.dart';
import '../services/cf_clearance_refresh_service.dart';
import '../services/network/cookie/android_cdp_feature.dart';
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
  /// Android 原生 CDP Cookie 同步
  final bool androidNativeCdp;
  /// 竖屏锁定
  final bool portraitLock;
  /// 滚动时收起顶栏和底栏
  final bool hideBarOnScroll;
  /// 退出时清除图片缓存
  final bool clearCacheOnExit;
  /// cf_clearance 自动续期
  final bool cfClearanceRefresh;
  /// 相关链接默认展开
  final bool expandRelatedLinks;
  /// AI 助手左滑入口（PageView 模式）
  final bool aiSwipeEntry;
  /// 对话框背景高斯模糊
  final bool dialogBlur;
  /// 最大并发请求数
  final int maxConcurrent;
  /// 滑动窗口内最大请求数
  final int maxPerWindow;
  /// 滑动窗口时长（秒）
  final int windowSeconds;
  /// 底栏：单击已选中 tab 执行的动作
  final NavTapAction bottomSingleTapAction;
  /// 底栏：双击已选中 tab 执行的动作
  final NavTapAction bottomDoubleTapAction;
  /// 底栏入口 id 列表（顺序即显示顺序）
  final List<String> bottomNavIds;

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
    required this.androidNativeCdp,
    required this.portraitLock,
    required this.hideBarOnScroll,
    required this.clearCacheOnExit,
    required this.cfClearanceRefresh,
    required this.expandRelatedLinks,
    required this.aiSwipeEntry,
    required this.dialogBlur,
    required this.maxConcurrent,
    required this.maxPerWindow,
    required this.windowSeconds,
    required this.bottomSingleTapAction,
    required this.bottomDoubleTapAction,
    required this.bottomNavIds,
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
    bool? androidNativeCdp,
    bool? portraitLock,
    bool? hideBarOnScroll,
    bool? clearCacheOnExit,
    bool? cfClearanceRefresh,
    bool? expandRelatedLinks,
    bool? aiSwipeEntry,
    bool? dialogBlur,
    int? maxConcurrent,
    int? maxPerWindow,
    int? windowSeconds,
    NavTapAction? bottomSingleTapAction,
    NavTapAction? bottomDoubleTapAction,
    List<String>? bottomNavIds,
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
      androidNativeCdp: androidNativeCdp ?? this.androidNativeCdp,
      portraitLock: portraitLock ?? this.portraitLock,
      hideBarOnScroll: hideBarOnScroll ?? this.hideBarOnScroll,
      clearCacheOnExit: clearCacheOnExit ?? this.clearCacheOnExit,
      cfClearanceRefresh: cfClearanceRefresh ?? this.cfClearanceRefresh,
      expandRelatedLinks: expandRelatedLinks ?? this.expandRelatedLinks,
      aiSwipeEntry: aiSwipeEntry ?? this.aiSwipeEntry,
      dialogBlur: dialogBlur ?? this.dialogBlur,
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      maxPerWindow: maxPerWindow ?? this.maxPerWindow,
      windowSeconds: windowSeconds ?? this.windowSeconds,
      bottomSingleTapAction:
          bottomSingleTapAction ?? this.bottomSingleTapAction,
      bottomDoubleTapAction:
          bottomDoubleTapAction ?? this.bottomDoubleTapAction,
      bottomNavIds: bottomNavIds ?? this.bottomNavIds,
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
  static const String _androidNativeCdpKey = AndroidCdpFeature.prefKey;
  static const String _portraitLockKey = 'pref_portrait_lock';
  static const String _hideBarOnScrollKey = 'pref_hide_bar_on_scroll';
  static const String _clearCacheOnExitKey = 'pref_clear_cache_on_exit';
  static const String _cfClearanceRefreshKey =
      CfClearanceRefreshService.prefKeyEnabled;
  static const String _expandRelatedLinksKey = 'pref_expand_related_links';
  static const String _aiSwipeEntryKey = 'pref_ai_swipe_entry';
  static const String _dialogBlurKey = 'pref_dialog_blur';
  static const String _maxConcurrentKey = 'pref_max_concurrent';
  static const String _maxPerWindowKey = 'pref_max_per_window';
  static const String _windowSecondsKey = 'pref_window_seconds';
  static const String _bottomSingleTapActionKey =
      'pref_bottom_single_tap_action';
  static const String _bottomDoubleTapActionKey =
      'pref_bottom_double_tap_action';
  static const String _bottomNavIdsKey = 'pref_bottom_nav_ids';

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
            crashlytics: _prefs.getBool(_crashlyticsKey) ?? true,
            androidNativeCdp: _prefs.getBool(_androidNativeCdpKey) ?? false,
            portraitLock: _prefs.getBool(_portraitLockKey) ?? false,
            hideBarOnScroll: _prefs.getBool(_hideBarOnScrollKey) ?? true,
            clearCacheOnExit: _prefs.getBool(_clearCacheOnExitKey) ?? false,
            cfClearanceRefresh:
                _prefs.getBool(_cfClearanceRefreshKey) ?? false,
            expandRelatedLinks:
                _prefs.getBool(_expandRelatedLinksKey) ?? false,
            aiSwipeEntry: _prefs.getBool(_aiSwipeEntryKey) ?? false,
            dialogBlur: _prefs.getBool(_dialogBlurKey) ?? true,
            maxConcurrent: _prefs.getInt(_maxConcurrentKey) ?? 3,
            maxPerWindow: _prefs.getInt(_maxPerWindowKey) ?? 6,
            windowSeconds: _prefs.getInt(_windowSecondsKey) ?? 3,
            bottomSingleTapAction: NavTapActionX.fromStorageKey(
              _prefs.getString(_bottomSingleTapActionKey),
              fallback: NavTapAction.scrollToTop,
            ),
            bottomDoubleTapAction: NavTapActionX.fromStorageKey(
              _prefs.getString(_bottomDoubleTapActionKey),
              fallback: NavTapAction.refresh,
            ),
            bottomNavIds: _prefs.getStringList(_bottomNavIdsKey) ??
                const [NavEntryIds.home, NavEntryIds.profile],
          ),
        ) {
    isPortraitLocked = state.portraitLock;
    _syncSchedulerConfig();
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

  Future<void> setAndroidNativeCdp(bool enabled) async {
    state = state.copyWith(androidNativeCdp: enabled);
    await AndroidCdpFeature.setEnabled(enabled);
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

  Future<void> setCfClearanceRefresh(bool enabled) async {
    state = state.copyWith(cfClearanceRefresh: enabled);
    await CfClearanceRefreshService().setEnabled(enabled);
  }

  Future<void> setExpandRelatedLinks(bool enabled) async {
    state = state.copyWith(expandRelatedLinks: enabled);
    await _prefs.setBool(_expandRelatedLinksKey, enabled);
  }

  Future<void> setAiSwipeEntry(bool enabled) async {
    state = state.copyWith(aiSwipeEntry: enabled);
    await _prefs.setBool(_aiSwipeEntryKey, enabled);
  }

  Future<void> setDialogBlur(bool enabled) async {
    state = state.copyWith(dialogBlur: enabled);
    await _prefs.setBool(_dialogBlurKey, enabled);
  }

  Future<void> setMaxConcurrent(int value) async {
    final clamped = value.clamp(1, 10);
    state = state.copyWith(maxConcurrent: clamped);
    await _prefs.setInt(_maxConcurrentKey, clamped);
    RequestSchedulerConfig.maxConcurrent = clamped;
  }

  Future<void> setMaxPerWindow(int value) async {
    final clamped = value.clamp(2, 30);
    state = state.copyWith(maxPerWindow: clamped);
    await _prefs.setInt(_maxPerWindowKey, clamped);
    RequestSchedulerConfig.maxPerWindow = clamped;
  }

  Future<void> setWindowSeconds(int value) async {
    final clamped = value.clamp(1, 10);
    state = state.copyWith(windowSeconds: clamped);
    await _prefs.setInt(_windowSecondsKey, clamped);
    RequestSchedulerConfig.windowSeconds = clamped;
  }

  Future<void> setBottomSingleTapAction(NavTapAction action) async {
    state = state.copyWith(bottomSingleTapAction: action);
    await _prefs.setString(_bottomSingleTapActionKey, action.toStorageKey());
  }

  Future<void> setBottomDoubleTapAction(NavTapAction action) async {
    state = state.copyWith(bottomDoubleTapAction: action);
    await _prefs.setString(_bottomDoubleTapActionKey, action.toStorageKey());
  }

  /// 写入底栏 id 列表（顺序即显示顺序）。调用方负责校验。
  Future<void> setBottomNavIds(List<String> ids) async {
    state = state.copyWith(bottomNavIds: ids);
    await _prefs.setStringList(_bottomNavIdsKey, ids);
  }

  void _syncSchedulerConfig() {
    RequestSchedulerConfig.maxConcurrent = state.maxConcurrent;
    RequestSchedulerConfig.maxPerWindow = state.maxPerWindow;
    RequestSchedulerConfig.windowSeconds = state.windowSeconds;
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
