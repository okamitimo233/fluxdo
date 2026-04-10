import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nested_topic.dart';
import '../models/topic.dart';
import 'core_providers.dart';

/// 嵌套视图参数
class NestedTopicParams {
  final int topicId;

  const NestedTopicParams({required this.topicId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NestedTopicParams && topicId == other.topicId;

  @override
  int get hashCode => topicId.hashCode;
}

/// 嵌套视图状态
class NestedTopicState {
  final Map<String, dynamic>? topicJson;
  final Post? opPost;
  final List<NestedNode> roots;
  final bool hasMoreRoots;
  final int currentPage;
  final String sort;
  final List<int>? pinnedPostIds;
  final bool isLoadingMore;

  const NestedTopicState({
    this.topicJson,
    this.opPost,
    this.roots = const [],
    this.hasMoreRoots = false,
    this.currentPage = 0,
    this.sort = 'old',
    this.pinnedPostIds,
    this.isLoadingMore = false,
  });

  String get title => topicJson?['title'] as String? ?? '';

  NestedTopicState copyWith({
    Map<String, dynamic>? topicJson,
    Post? opPost,
    List<NestedNode>? roots,
    bool? hasMoreRoots,
    int? currentPage,
    String? sort,
    List<int>? pinnedPostIds,
    bool? isLoadingMore,
  }) {
    return NestedTopicState(
      topicJson: topicJson ?? this.topicJson,
      opPost: opPost ?? this.opPost,
      roots: roots ?? this.roots,
      hasMoreRoots: hasMoreRoots ?? this.hasMoreRoots,
      currentPage: currentPage ?? this.currentPage,
      sort: sort ?? this.sort,
      pinnedPostIds: pinnedPostIds ?? this.pinnedPostIds,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// 嵌套视图 Notifier
class NestedTopicNotifier extends AsyncNotifier<NestedTopicState> {
  NestedTopicNotifier(this.arg);
  final NestedTopicParams arg;

  @override
  Future<NestedTopicState> build() async {
    final service = ref.read(discourseServiceProvider);
    final response = await service.getNestedRoots(arg.topicId, sort: 'old', page: 0);

    return NestedTopicState(
      topicJson: response.topicJson,
      opPost: response.opPost,
      roots: response.roots,
      hasMoreRoots: response.hasMoreRoots,
      currentPage: 0,
      sort: response.sort ?? 'old',
      pinnedPostIds: response.pinnedPostIds,
    );
  }

  /// 加载更多根帖子
  Future<void> loadMoreRoots() async {
    final current = state.value;
    if (current == null || !current.hasMoreRoots || current.isLoadingMore) return;

    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final service = ref.read(discourseServiceProvider);
      final nextPage = current.currentPage + 1;
      final response = await service.getNestedRoots(
        arg.topicId,
        sort: current.sort,
        page: nextPage,
      );

      if (!ref.mounted) return;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state = AsyncValue.data(current.copyWith(
        roots: [...current.roots, ...response.roots],
        hasMoreRoots: response.hasMoreRoots,
        currentPage: nextPage,
        isLoadingMore: false,
      ));
    } catch (e) {
      debugPrint('[NestedTopic] loadMoreRoots failed: $e');
      if (!ref.mounted) return;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state = AsyncValue.data(current.copyWith(isLoadingMore: false));
    }
  }

  /// 切换排序
  Future<void> changeSort(String newSort) async {
    final current = state.value;
    if (current == null || current.sort == newSort) return;

    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    state = const AsyncValue.loading();

    try {
      final service = ref.read(discourseServiceProvider);
      final response = await service.getNestedRoots(arg.topicId, sort: newSort, page: 0);

      if (!ref.mounted) return;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state = AsyncValue.data(NestedTopicState(
        topicJson: current.topicJson,
        opPost: current.opPost,
        roots: response.roots,
        hasMoreRoots: response.hasMoreRoots,
        currentPage: 0,
        sort: newSort,
        pinnedPostIds: response.pinnedPostIds,
      ));
    } catch (e, s) {
      if (!ref.mounted) return;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state = AsyncValue.error(e, s);
    }
  }

  /// 懒加载子回复
  Future<NestedChildrenResponse> loadChildren(int postNumber, {int page = 0, int depth = 1}) async {
    final current = state.value;
    final service = ref.read(discourseServiceProvider);
    return service.getNestedChildren(
      arg.topicId,
      postNumber,
      sort: current?.sort ?? 'old',
      page: page,
      depth: depth,
    );
  }
}

final nestedTopicProvider = AsyncNotifierProvider.family.autoDispose<NestedTopicNotifier, NestedTopicState, NestedTopicParams>(
  NestedTopicNotifier.new,
);
