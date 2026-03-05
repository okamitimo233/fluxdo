// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme_provider.dart';

/// 话题列表筛选模式
enum TopicListFilter {
  latest,
  newTopics,
  unread,
  unseen,
  top,
  hot,
}

/// TopicListFilter 扩展方法
extension TopicListFilterX on TopicListFilter {
  /// 获取 API 请求所用的过滤器名称
  String get filterName {
    switch (this) {
      case TopicListFilter.latest:
        return 'latest';
      case TopicListFilter.newTopics:
        return 'new';
      case TopicListFilter.unread:
        return 'unread';
      case TopicListFilter.unseen:
        return 'unseen';
      case TopicListFilter.top:
        return 'top';
      case TopicListFilter.hot:
        return 'top';
    }
  }

  /// 获取 top 排序的周期参数（仅 top/hot 有效）
  String? get period {
    switch (this) {
      case TopicListFilter.hot:
        return 'weekly';
      default:
        return null;
    }
  }
}

/// 话题筛选条件（内部使用）
class TopicFilterParams {
  final int? categoryId;
  final String? categorySlug;
  final String? categoryName;
  final String? parentCategorySlug;
  final List<String> tags;

  const TopicFilterParams({
    this.categoryId,
    this.categorySlug,
    this.categoryName,
    this.parentCategorySlug,
    this.tags = const [],
  });

  bool get isEmpty => categoryId == null && tags.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// 筛选模式持久化 Notifier
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
