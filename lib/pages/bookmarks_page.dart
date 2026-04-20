import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/search_filter.dart';
import '../models/topic.dart';
import '../navigation/nav_action_bus.dart';
import '../providers/discourse_providers.dart';
import '../providers/preferences_provider.dart';
import '../providers/user_content_search_provider.dart';
import '../services/app_error_handler.dart';
import '../services/discourse/discourse_service.dart';
import '../services/toast_service.dart';
import '../utils/time_utils.dart';
import '../widgets/bookmark/bookmark_edit_sheet.dart';
import '../widgets/search/searchable_app_bar.dart';
import '../widgets/search/user_content_search_view.dart';
import '../widgets/topic/topic_item_builder.dart';
import '../widgets/topic/topic_list_skeleton.dart';
import '../widgets/topic/topic_preview_dialog.dart';
import '../widgets/common/error_view.dart';
import '../l10n/s.dart';
import '../widgets/desktop_refresh_indicator.dart';
import 'topic_detail_page/topic_detail_page.dart';

/// 我的书签页面
class BookmarksPage extends ConsumerStatefulWidget {
  const BookmarksPage({super.key, this.isActive = true});

  /// 是否为当前活跃的 tab（嵌入底栏时用于决定是否响应 NavActionBus）
  final bool isActive;

  @override
  ConsumerState<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends ConsumerState<BookmarksPage> {
  final ScrollController _scrollController = ScrollController();
  late final UserContentSearchNotifier _searchNotifier;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchNotifier = ref.read(userContentSearchProvider(SearchInType.bookmarks).notifier);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    Future(_searchNotifier.exitSearchMode);
    super.dispose();
  }

  void _onScroll() {
    _publishScrollProgress();
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(bookmarksProvider.notifier).loadMore();
    }
  }

  void _publishScrollProgress() {
    if (!_scrollController.hasClients) return;
    final raw = _scrollController.offset;
    final progress = raw < 0 ? 0.0 : raw;
    final current = ref.read(navScrollProgressProvider(NavEntryIds.bookmarks));
    final atZero = progress == 0 && current != 0;
    final crossed = (progress >= navScrollIconThreshold) !=
        (current >= navScrollIconThreshold);
    if (!atZero && !crossed && (progress - current).abs() < 4.0) return;
    ref.read(navScrollProgressProvider(NavEntryIds.bookmarks).notifier).state =
        progress;
  }

  Future<void> _onRefresh() async {
    await ref.read(bookmarksProvider.notifier).refresh();
  }

  void _onItemTap(Topic topic) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: topic.id,
          // 帖子书签跳转到被书签的帖子，话题书签使用最后阅读位置
          scrollToPostNumber: topic.bookmarkedPostNumber ?? topic.lastReadPostNumber,
        ),
      ),
    );
  }

  @override

  @override
  Widget build(BuildContext context) {
    final bookmarksAsync = ref.watch(bookmarksProvider);
    final searchState = ref.watch(userContentSearchProvider(SearchInType.bookmarks));

    // 嵌入底栏时响应快捷动作（仅活跃 tab 响应）
    ref.listen(navActionBusProvider, (_, event) {
      if (event == null || event.targetId != NavEntryIds.bookmarks) return;
      if (!widget.isActive) return;
      switch (event.action) {
        case NavAction.scrollToTop:
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
          break;
        case NavAction.refresh:
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
          _onRefresh();
          ref.resetNavScrollProgress(NavEntryIds.bookmarks);
          break;
      }
    });

    return PopScope(
      canPop: !searchState.isSearchMode,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          // 搜索模式下按返回键，退出搜索而不是退出页面
          ref.read(userContentSearchProvider(SearchInType.bookmarks).notifier).exitSearchMode();
        }
      },
      child: Scaffold(
        appBar: SearchableAppBar(
          title: context.l10n.bookmarks_title,
          isSearchMode: searchState.isSearchMode,
          onSearchPressed: () => ref
              .read(userContentSearchProvider(SearchInType.bookmarks).notifier)
              .enterSearchMode(),
          onCloseSearch: () => ref
              .read(userContentSearchProvider(SearchInType.bookmarks).notifier)
              .exitSearchMode(),
          onSearch: (query) => ref
              .read(userContentSearchProvider(SearchInType.bookmarks).notifier)
              .search(query),
          showFilterButton: searchState.isSearchMode,
          filterActive: searchState.filter.isNotEmpty,
          onFilterPressed: () =>
              showSearchFilterPanel(context, ref, SearchInType.bookmarks),
          searchHint: context.l10n.bookmarks_searchHint,
        ),
        body: Stack(
          children: [
            // 使用 Offstage 保持列表存在但在搜索模式下隐藏，保留滚动位置
            Offstage(
              offstage: searchState.isSearchMode,
              child: _buildTopicList(bookmarksAsync),
            ),
            if (searchState.isSearchMode)
              UserContentSearchView(
                inType: SearchInType.bookmarks,
                emptySearchHint: context.l10n.bookmarks_emptySearchHint,
              ),
          ],
        ),
      ),
    );
  }

  /// 卡片顶部色带：书签名称、提醒时间
  Widget? _buildBookmarkTopBar(BuildContext context, Topic topic) {
    final hasName = topic.bookmarkName != null && topic.bookmarkName!.isNotEmpty;
    final hasReminder = topic.bookmarkReminderAt != null;
    if (!hasName && !hasReminder) return null;

    final colorScheme = Theme.of(context).colorScheme;
    final isExpired = hasReminder &&
        topic.bookmarkReminderAt!.isBefore(DateTime.now());
    final bgColor = isExpired
        ? colorScheme.errorContainer.withValues(alpha: 0.5)
        : colorScheme.secondaryContainer.withValues(alpha: 0.6);
    final fgColor = isExpired
        ? colorScheme.error
        : colorScheme.onSecondaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: bgColor,
      child: Text.rich(
        TextSpan(
          children: [
            // 书签名称
            if (hasName) ...[
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.bookmark_outlined, size: 13, color: fgColor),
              ),
              TextSpan(text: ' ${topic.bookmarkName!}'),
            ],
            // 提醒时间
            if (hasReminder) ...[
              if (hasName)
                TextSpan(
                  text: '  ·  ',
                  style: TextStyle(color: fgColor.withValues(alpha: 0.4)),
                ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.alarm, size: 13, color: fgColor),
              ),
              TextSpan(
                text: isExpired
                    ? context.l10n.bookmarks_expired
                    : ' ${TimeUtils.formatDetailTime(topic.bookmarkReminderAt!)}',
              ),
            ],
          ],
        ),
        style: TextStyle(
          fontSize: 12,
          color: fgColor,
          height: 1.3,
        ),
      ),
    );
  }

  /// 卡片底部：摘要
  Widget? _buildBookmarkExcerpt(BuildContext context, Topic topic) {
    if (topic.excerpt == null) return null;
    final cleaned = _cleanExcerpt(topic.excerpt!);
    if (cleaned.isEmpty) return null;

    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      cleaned,
      style: TextStyle(
        fontSize: 12,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        height: 1.4,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 清理 excerpt 中的 HTML 标签和实体
  String _cleanExcerpt(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&hellip;', '...')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<PreviewAction> _buildPreviewActions(Topic topic) {
    final theme = Theme.of(context);
    final bookmarkId = topic.bookmarkId;
    if (bookmarkId == null) return [];

    return [
      PreviewAction(
        icon: Icons.edit_outlined,
        label: context.l10n.bookmark_editBookmark,
        color: theme.colorScheme.primary,
        onTap: () => _editBookmark(topic),
      ),
      if (topic.bookmarkReminderAt != null)
        PreviewAction(
          icon: Icons.alarm_off,
          label: context.l10n.bookmarks_cancelReminder,
          onTap: () => _clearReminder(topic),
        ),
      PreviewAction(
        icon: Icons.delete_outline,
        label: context.l10n.common_deleteBookmark,
        color: theme.colorScheme.error,
        onTap: () => _deleteBookmark(topic),
      ),
    ];
  }

  Future<void> _editBookmark(Topic topic) async {
    final bookmarkId = topic.bookmarkId;
    if (bookmarkId == null) return;

    final result = await BookmarkEditSheet.show(
      context,
      bookmarkId: bookmarkId,
      initialName: topic.bookmarkName,
      initialReminderAt: topic.bookmarkReminderAt,
    );
    if (result == null || !mounted) return;

    final notifier = ref.read(bookmarksProvider.notifier);
    if (result.deleted) {
      notifier.removeBookmarkById(bookmarkId);
    } else {
      notifier.updateBookmarkMeta(
        bookmarkId,
        name: result.name,
        reminderAt: result.reminderAt,
        clearReminderAt: result.reminderAt == null,
      );
    }
  }

  Future<void> _clearReminder(Topic topic) async {
    final bookmarkId = topic.bookmarkId;
    if (bookmarkId == null) return;

    try {
      await DiscourseService().clearBookmarkReminder(bookmarkId);
      if (!mounted) return;
      ref.read(bookmarksProvider.notifier).updateBookmarkMeta(
        bookmarkId,
        clearReminderAt: true,
      );
      ToastService.showSuccess(S.current.bookmarks_reminderCancelled);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _deleteBookmark(Topic topic) async {
    final bookmarkId = topic.bookmarkId;
    if (bookmarkId == null) return;

    try {
      await DiscourseService().deleteBookmark(bookmarkId);
      if (!mounted) return;
      ref.read(bookmarksProvider.notifier).removeBookmarkById(bookmarkId);
      ToastService.showSuccess(S.current.bookmarks_deleted);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Widget _buildTopicList(AsyncValue<List<Topic>> bookmarksAsync) {
    return DesktopRefreshIndicator(
      onRefresh: _onRefresh,
      child: bookmarksAsync.when(
        data: (topics) {
          if (topics.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(context.l10n.bookmarks_empty, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: topics.length + 1,
            itemBuilder: (context, index) {
              if (index == topics.length) {
                final notifier = ref.watch(bookmarksProvider.notifier);
                if (!notifier.hasMore) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        context.l10n.common_noMore,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }
                if (notifier.isLoadMoreFailed) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: GestureDetector(
                        onTap: () => notifier.retryLoadMore(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh, size: 16, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              context.l10n.common_loadFailedTapRetry,
                              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                if (bookmarksAsync.isLoading && !bookmarksAsync.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return const SizedBox();
              }

              final topic = topics[index];
              final enableLongPress = ref.watch(preferencesProvider).longPressPreview;
              return buildTopicItem(
                context: context,
                topic: topic,
                isSelected: false,
                onTap: () => _onItemTap(topic),
                enableLongPress: enableLongPress,
                topWidget: _buildBookmarkTopBar(context, topic),
                bottomWidget: _buildBookmarkExcerpt(context, topic),
                previewActions: topic.bookmarkId != null
                    ? _buildPreviewActions(topic)
                    : null,
              );
            },
          );
        },
        loading: () => const TopicListSkeleton(),
        error: (error, stack) => ErrorView(
          error: error,
          stackTrace: stack,
          onRetry: _onRefresh,
        ),
      ),
    );
  }
}
