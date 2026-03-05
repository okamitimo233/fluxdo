import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'filter_provider.dart';
import 'sort_provider.dart';

/// 每个 tab 独立的标签筛选（categoryId -> tags）
/// null 表示"全部"tab
final tabTagsProvider = StateProvider.family<List<String>, int?>((ref, categoryId) => []);

/// 当前选中 tab 对应的分类 ID（null 表示"全部"tab）
final currentTabCategoryIdProvider = StateProvider<int?>((ref) => null);

/// 话题列表 tab 失活信号
/// refreshAll 时递增，通知非当前 tab 释放 keepAlive
final topicTabDeactivateSignal = StateProvider<int>((ref) => 0);

/// 话题列表全局参数变化信号
/// watch 了所有影响话题列表的全局参数，任一变化都会触发 rebuild
/// UI 层只需 listen 此信号即可感知所有参数变化
/// 未来新增全局筛选条件时，只需在此添加 ref.watch
final topicListGlobalParamsSignal = Provider<Object>((ref) {
  ref.watch(topicFilterProvider);
  ref.watch(topicSortOrderProvider);
  ref.watch(topicSortAscendingProvider);
  return Object();
});
