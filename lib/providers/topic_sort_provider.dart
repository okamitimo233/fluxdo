// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'topic_list_provider.dart';
import 'theme_provider.dart';

/// 筛选模式持久化 Notifier（原 TopicSortNotifier）
class TopicFilterNotifier extends StateNotifier<TopicListFilter> {
  static const String _key = 'topic_sort_filter';
  final SharedPreferences _prefs;

  TopicFilterNotifier(this._prefs)
      : super(_fromName(_prefs.getString(_key)));

  static TopicListFilter _fromName(String? name) {
    for (final filter in TopicListFilter.values) {
      if (filter.name == name) return filter;
    }
    return TopicListFilter.latest;
  }

  void setFilter(TopicListFilter filter) {
    state = filter;
    _prefs.setString(_key, filter.name);
  }
}

/// 当前筛选模式（持久化到 SharedPreferences）
final topicFilterProvider =
    StateNotifierProvider<TopicFilterNotifier, TopicListFilter>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TopicFilterNotifier(prefs);
});

// ─── 排序（真正的字段排序）───

/// 话题排序字段
enum TopicSortOrder {
  /// 默认（不传 order 参数，由 API 决定）
  defaultOrder,
  /// 活跃度（bumped_at）
  activity,
  /// 创建时间
  created,
  /// 点赞数
  likes,
  /// 浏览量
  views,
  /// 回复数
  posts,
  /// 参与者数
  posters,
}

extension TopicSortOrderX on TopicSortOrder {
  /// 返回 API order 参数值，defaultOrder 返回 null
  String? get apiValue {
    switch (this) {
      case TopicSortOrder.defaultOrder:
        return null;
      case TopicSortOrder.activity:
        return 'activity';
      case TopicSortOrder.created:
        return 'created';
      case TopicSortOrder.likes:
        return 'likes';
      case TopicSortOrder.views:
        return 'views';
      case TopicSortOrder.posts:
        return 'posts';
      case TopicSortOrder.posters:
        return 'posters';
    }
  }

  /// 中文显示名称
  String get label {
    switch (this) {
      case TopicSortOrder.defaultOrder:
        return '默认';
      case TopicSortOrder.activity:
        return '活跃度';
      case TopicSortOrder.created:
        return '创建时间';
      case TopicSortOrder.likes:
        return '点赞数';
      case TopicSortOrder.views:
        return '浏览量';
      case TopicSortOrder.posts:
        return '回复数';
      case TopicSortOrder.posters:
        return '参与者';
    }
  }
}

/// 排序字段持久化 Notifier
class TopicSortOrderNotifier extends StateNotifier<TopicSortOrder> {
  static const String _key = 'topic_sort_order';
  final SharedPreferences _prefs;

  TopicSortOrderNotifier(this._prefs)
      : super(_fromName(_prefs.getString(_key)));

  static TopicSortOrder _fromName(String? name) {
    for (final order in TopicSortOrder.values) {
      if (order.name == name) return order;
    }
    return TopicSortOrder.defaultOrder;
  }

  void setOrder(TopicSortOrder order) {
    state = order;
    _prefs.setString(_key, order.name);
  }
}

/// 当前排序字段（持久化到 SharedPreferences）
final topicSortOrderProvider =
    StateNotifierProvider<TopicSortOrderNotifier, TopicSortOrder>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TopicSortOrderNotifier(prefs);
});

/// 升降序持久化 Notifier
class TopicSortAscendingNotifier extends StateNotifier<bool> {
  static const String _key = 'topic_sort_ascending';
  final SharedPreferences _prefs;

  TopicSortAscendingNotifier(this._prefs)
      : super(_prefs.getBool(_key) ?? false);

  void setAscending(bool ascending) {
    state = ascending;
    _prefs.setBool(_key, ascending);
  }

  void toggle() {
    setAscending(!state);
  }
}

/// 排序方向（持久化到 SharedPreferences，默认 false 即降序）
final topicSortAscendingProvider =
    StateNotifierProvider<TopicSortAscendingNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TopicSortAscendingNotifier(prefs);
});

/// 每个 tab 独立的标签筛选（categoryId -> tags）
/// null 表示"全部"tab
final tabTagsProvider = StateProvider.family<List<String>, int?>((ref, categoryId) => []);

/// 当前选中 tab 对应的分类 ID（null 表示"全部"tab）
final currentTabCategoryIdProvider = StateProvider<int?>((ref) => null);

/// 话题列表 tab 失活信号
/// refreshAll 时递增，通知非当前 tab 释放 keepAlive
final topicTabDeactivateSignal = StateProvider<int>((ref) => 0);
