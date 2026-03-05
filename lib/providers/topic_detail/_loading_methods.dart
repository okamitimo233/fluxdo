part of '../topic_detail_provider.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

/// 加载相关方法
extension LoadingMethods on TopicDetailNotifier {
  /// 加载更早的帖子（向上滚动）
  Future<void> loadPrevious() async {
    if (_isLoadPreviousFailed) return; // 失败后需手动重试
    if (_isFilteredMode) {
      if (!_hasMoreBefore || state.isLoading || _isLoadingPrevious) return;
      await _loadPreviousByStreamIds();
      return;
    }
    if (!_hasMoreBefore || state.isLoading || _isLoadingPrevious) return;
    _isLoadingPrevious = true;

    try {
      // ignore: invalid_use_of_internal_member
      state = const AsyncLoading<TopicDetail>().copyWithPrevious(state);

      final result = await AsyncValue.guard(() async {
        final currentDetail = state.requireValue;
        final currentPosts = currentDetail.postStream.posts;
        final stream = currentDetail.postStream.stream;

        if (currentPosts.isEmpty) {
          _hasMoreBefore = false;
          return currentDetail;
        }

        final firstPostId = currentPosts.first.id;
        final firstIndex = stream.indexOf(firstPostId);
        if (firstIndex <= 0) {
          _hasMoreBefore = false;
          return currentDetail;
        }

        final firstPostNumber = currentPosts.first.postNumber;
        final service = ref.read(discourseServiceProvider);
        final newPostStream = await service.getPostsByNumber(
          arg.topicId,
          postNumber: firstPostNumber,
          asc: false,
        );

        final existingIds = currentPosts.map((p) => p.id).toSet();
        final newPosts = newPostStream.posts.where((p) => !existingIds.contains(p.id)).toList();
        final mergedPosts = [...newPosts, ...currentPosts];
        mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

        final currentStream = currentDetail.postStream.stream;
        final existingStreamIds = currentStream.toSet();
        final newPostIds = newPosts.map((p) => p.id).where((id) => !existingStreamIds.contains(id)).toList();
        final mergedStream = [...newPostIds, ...currentStream];

        final newFirstId = mergedPosts.first.id;
        final newFirstIndex = mergedStream.indexOf(newFirstId);
        _hasMoreBefore = newFirstIndex > 0;

        return currentDetail.copyWith(
          postStream: PostStream(posts: mergedPosts, stream: mergedStream, gaps: currentDetail.postStream.gaps),
        );
      });
      if (!ref.mounted) return;
      if (result.hasError) {
        _isLoadPreviousFailed = true;
        // 恢复之前的数据状态，不让 UI 显示全局错误
        state = AsyncValue.data(state.requireValue);
      } else {
        state = result;
      }
    } finally {
      _isLoadingPrevious = false;
    }
  }

  /// 手动重试加载更早的帖子
  Future<void> retryLoadPrevious() async {
    _isLoadPreviousFailed = false;
    await loadPrevious();
  }

  /// 加载更多回复（向下滚动）
  Future<void> loadMore() async {
    if (_isLoadMoreFailed) return; // 失败后需手动重试
    if (!_hasMoreAfter || state.isLoading || _isLoadingMore) return;

    if (_isFilteredMode) {
      await _loadMoreByStreamIds();
      return;
    }
    _isLoadingMore = true;

    try {
      // ignore: invalid_use_of_internal_member
      state = const AsyncLoading<TopicDetail>().copyWithPrevious(state);

      final result = await AsyncValue.guard(() async {
        final currentDetail = state.requireValue;
        final currentPosts = currentDetail.postStream.posts;
        final stream = currentDetail.postStream.stream;

        if (currentPosts.isEmpty) {
          _hasMoreAfter = false;
          return currentDetail;
        }

        final lastPostId = currentPosts.last.id;
        final lastIndex = stream.indexOf(lastPostId);
        if (lastIndex == -1 || lastIndex >= stream.length - 1) {
          _hasMoreAfter = false;
          return currentDetail;
        }

        final lastPostNumber = currentPosts.last.postNumber;
        final service = ref.read(discourseServiceProvider);
        final newPostStream = await service.getPostsByNumber(
          arg.topicId,
          postNumber: lastPostNumber,
          asc: true,
        );

        final existingIds = currentPosts.map((p) => p.id).toSet();
        final newPosts = newPostStream.posts.where((p) => !existingIds.contains(p.id)).toList();
        final mergedPosts = [...currentPosts, ...newPosts];
        mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

        final currentStream = currentDetail.postStream.stream;
        final existingStreamIds = currentStream.toSet();
        final newPostIds = newPosts.map((p) => p.id).where((id) => !existingStreamIds.contains(id)).toList();
        final mergedStream = [...currentStream, ...newPostIds];

        final newLastId = mergedPosts.last.id;
        final newLastIndex = mergedStream.indexOf(newLastId);
        _hasMoreAfter = newLastIndex < mergedStream.length - 1;

        return currentDetail.copyWith(
          postStream: PostStream(posts: mergedPosts, stream: mergedStream, gaps: currentDetail.postStream.gaps),
        );
      });
      if (!ref.mounted) return;
      if (result.hasError) {
        _isLoadMoreFailed = true;
        state = AsyncValue.data(state.requireValue);
      } else {
        state = result;
      }
    } finally {
      _isLoadingMore = false;
    }
  }

  /// 手动重试加载更多
  Future<void> retryLoadMore() async {
    _isLoadMoreFailed = false;
    await loadMore();
  }

  /// 加载新回复（用于 MessageBus 实时更新）
  Future<void> loadNewReplies() async {
    if (state.isLoading) return;
    if (_isFilteredMode) return; // 过滤模式下忽略

    final currentDetail = state.value;
    if (currentDetail == null) return;

    final currentPosts = currentDetail.postStream.posts;
    if (currentPosts.isEmpty) return;

    final lastPostNumber = currentPosts.last.postNumber;

    // 用户不在底部：只更新 stream 和 postsCount（让进度指示器反映新帖子）
    if (lastPostNumber < currentDetail.postsCount) {
      try {
        final service = ref.read(discourseServiceProvider);
        // 轻量请求：只获取最新话题信息以拿到 stream 和 postsCount
        final newDetail = await service.getTopicDetail(arg.topicId, postNumber: lastPostNumber);
        if (newDetail.postStream.stream.length > currentDetail.postStream.stream.length) {
          if (!ref.mounted) return;
          state = AsyncValue.data(currentDetail.copyWith(
            postsCount: newDetail.postsCount,
            postStream: PostStream(
              posts: currentPosts,
              stream: newDetail.postStream.stream,
              gaps: currentDetail.postStream.gaps,
            ),
          ));
          _updateBoundaryState(currentPosts, newDetail.postStream.stream);
        }
      } catch (e) {
        debugPrint('[TopicDetail] 更新 stream 失败: $e');
      }
      return;
    }

    // 用户在底部：加载并追加新帖子
    final targetPostNumber = lastPostNumber + 1;

    try {
      final service = ref.read(discourseServiceProvider);
      final newDetail = await service.getTopicDetail(arg.topicId, postNumber: targetPostNumber);

      if (newDetail.postStream.posts.isEmpty) return;

      final existingIds = currentPosts.map((p) => p.id).toSet();
      final newPosts = newDetail.postStream.posts.where((p) => !existingIds.contains(p.id)).toList();

      if (newPosts.isEmpty) return;
      if (!ref.mounted) return;

      // 本地递增被回复帖子的 replyCount（与 Discourse 官方做法一致）
      final replyToNumbers = <int>{};
      for (final p in newPosts) {
        if (p.replyToPostNumber > 0) {
          replyToNumbers.add(p.replyToPostNumber);
        }
      }
      final updatedCurrentPosts = replyToNumbers.isEmpty
          ? currentPosts
          : currentPosts.map((p) {
              if (replyToNumbers.contains(p.postNumber)) {
                return p.copyWith(replyCount: p.replyCount + 1);
              }
              return p;
            }).toList();

      final mergedPosts = [...updatedCurrentPosts, ...newPosts];
      mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

      final mergedStream = newDetail.postStream.stream;

      _updateBoundaryState(mergedPosts, mergedStream);

      state = AsyncValue.data(currentDetail.copyWith(
        postsCount: newDetail.postsCount,
        postStream: PostStream(posts: mergedPosts, stream: mergedStream, gaps: currentDetail.postStream.gaps),
        canVote: newDetail.canVote,
        voteCount: newDetail.voteCount,
        userVoted: newDetail.userVoted,
      ));
    } catch (e) {
      debugPrint('[TopicDetail] 加载新回复失败: $e');
    }
  }

  /// 使用新的起始帖子号重新加载数据
  Future<void> reloadWithPostNumber(int postNumber) async {
    state = const AsyncValue.loading();
    _hasMoreAfter = true;
    _hasMoreBefore = true;
    _isLoadMoreFailed = false;
    _isLoadPreviousFailed = false;

    await Future.delayed(Duration.zero);

    final result = await AsyncValue.guard(() async {
      final service = ref.read(discourseServiceProvider);
      final detail = await service.getTopicDetail(
        arg.topicId,
        postNumber: postNumber,
        filter: _filter,
        usernameFilters: _usernameFilter,
      );

      _updateBoundaryState(detail.postStream.posts, detail.postStream.stream);

      return detail;
    });
    if (!ref.mounted) return;
    state = result;
  }

  /// 刷新当前话题详情（保持列表可见）
  Future<void> refreshWithPostNumber(int postNumber) async {
    if (state.isLoading) return;
    _isLoadMoreFailed = false;
    _isLoadPreviousFailed = false;

    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<TopicDetail>().copyWithPrevious(state);

    final result = await AsyncValue.guard(() async {
      final service = ref.read(discourseServiceProvider);
      final detail = await service.getTopicDetail(
        arg.topicId,
        postNumber: _isFilteredMode ? null : postNumber,
        filter: _filter,
        usernameFilters: _usernameFilter,
      );

      _updateBoundaryState(detail.postStream.posts, detail.postStream.stream);

      return detail;
    });
    if (!ref.mounted) return;
    state = result;
  }

  /// 加载指定楼层的帖子（用于跳转）
  Future<int> loadPostNumber(int postNumber) async {
    final currentDetail = state.value;
    if (currentDetail == null) return -1;

    final currentPosts = currentDetail.postStream.posts;

    final existingIndex = currentPosts.indexWhere((p) => p.postNumber == postNumber);
    if (existingIndex != -1) return existingIndex;

    try {
      final service = ref.read(discourseServiceProvider);
      final newDetail = await service.getTopicDetail(arg.topicId, postNumber: postNumber);

      final existingIds = currentPosts.map((p) => p.id).toSet();
      final newPosts = newDetail.postStream.posts.where((p) => !existingIds.contains(p.id)).toList();
      final mergedPosts = [...currentPosts, ...newPosts];
      mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

      final currentStream = currentDetail.postStream.stream;
      final newStream = newDetail.postStream.stream;
      final existingStreamIds = currentStream.toSet();
      final newStreamIds = newStream.where((id) => !existingStreamIds.contains(id)).toList();
      final mergedStream = [...currentStream, ...newStreamIds];

      _updateBoundaryState(mergedPosts, mergedStream);

      if (!ref.mounted) return -1;
      state = AsyncValue.data(currentDetail.copyWith(
        postStream: PostStream(posts: mergedPosts, stream: mergedStream, gaps: currentDetail.postStream.gaps),
      ));

      return mergedPosts.indexWhere((p) => p.postNumber == postNumber);
    } catch (e) {
      debugPrint('[TopicDetail] 加载帖子 #$postNumber 失败: $e');
      return -1;
    }
  }
}
