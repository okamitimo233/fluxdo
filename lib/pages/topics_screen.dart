import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/selected_topic_provider.dart';
import '../providers/discourse_providers.dart';
import '../providers/topic_sort_provider.dart';
import '../widgets/layout/master_detail_layout.dart';
import 'topics_page.dart';
import 'topic_detail_page/topic_detail_page.dart';
import 'create_topic_page.dart';

/// 话题屏幕
/// 在手机上显示单栏列表，平板上显示 Master-Detail 双栏
class TopicsScreen extends ConsumerStatefulWidget {
  const TopicsScreen({super.key, this.isActive = true});

  /// 是否为当前活跃的 tab（IndexedStack 中非活跃时跳过导航）
  final bool isActive;

  @override
  ConsumerState<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends ConsumerState<TopicsScreen> {
  bool? _lastCanShowDetailPane;
  bool _isAutoSwitching = false;

  /// 当前活跃的 provider 实例 ID，布局切换时复用
  String? _activeInstanceId;
  int? _activeTopicId;

  /// topicId 变化时生成新 instanceId，相同 topicId 复用
  /// 如果提供了 existingInstanceId（如从全屏详情页传回），直接采用
  String _getOrCreateInstanceId(int topicId, {String? existingInstanceId}) {
    if (existingInstanceId != null) {
      _activeTopicId = topicId;
      _activeInstanceId = existingInstanceId;
      return existingInstanceId;
    }
    if (_activeTopicId != topicId) {
      _activeTopicId = topicId;
      _activeInstanceId = const Uuid().v4();
    }
    return _activeInstanceId!;
  }

  void _maybePushDetail(SelectedTopicState selectedTopic, bool canShowDetailPane) {
    if (_isAutoSwitching) return;

    // IndexedStack 中非活跃 tab 仍需更新状态，避免切回时误触发
    if (!widget.isActive) {
      _lastCanShowDetailPane = canShowDetailPane;
      return;
    }

    // 当前路由不在栈顶时（有其他页面覆盖），根据布局判断是否清除选中
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      // 单栏模式下选中状态没有意义（看不到），清除并释放 provider 缓存
      if (!canShowDetailPane && selectedTopic.hasSelection) {
        _activeTopicId = null;
        _activeInstanceId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(selectedTopicProvider.notifier).clear();
        });
      }
      // 双栏模式下保留选中状态（从详情面板 push 到其他页面，回来还要显示）
      _lastCanShowDetailPane = canShowDetailPane;
      return;
    }

    final previous = _lastCanShowDetailPane;
    _lastCanShowDetailPane = canShowDetailPane;

    // 从双栏切到单栏时自动 push；如果 previous 为空但当前为单栏且有选中，
    // 也执行 push，避免因状态丢失导致无法自动进入详情。
    if (!canShowDetailPane && selectedTopic.hasSelection && (previous == null || previous == true)) {

      final topicId = selectedTopic.topicId;
      if (topicId == null) return;

      // 复用同一个 instanceId，避免重新 fetch
      final instanceId = _getOrCreateInstanceId(topicId);
      // 读取嵌入式详情页的实际浏览位置（在当前 build 中嵌入页还在 tree 中）
      final scrollPosition = ref.read(detailScrollPositionProvider(topicId))
          ?? selectedTopic.scrollToPostNumber;

      _isAutoSwitching = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final navigator = Navigator.of(context);
        ref.read(selectedTopicProvider.notifier).clear();
        navigator
            .push(
          MaterialPageRoute(
            builder: (_) => TopicDetailPage(
              topicId: topicId,
              initialTitle: selectedTopic.initialTitle,
              scrollToPostNumber: scrollPosition,
              autoSwitchToMasterDetail: true,
              instanceId: instanceId,
            ),
          ),
        )
            .whenComplete(() {
          if (mounted) {
            setState(() => _isAutoSwitching = false);
          }
        });
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTopic = ref.watch(selectedTopicProvider);
    final canShowDetailPane = MasterDetailLayout.canShowBothPanesFor(context);
    final user = ref.watch(currentUserProvider).value;

    _maybePushDetail(selectedTopic, canShowDetailPane);

    // 统一使用 MasterDetailLayout 处理所有情况
    // 手机/平板单栏：只显示 master
    // 平板双栏：显示 master + detail
    return MasterDetailLayout(
      master: const TopicsPage(),
      detail: selectedTopic.hasSelection && canShowDetailPane
          ? TopicDetailPane(
              key: ValueKey(selectedTopic.topicId),
              topicId: selectedTopic.topicId!,
              instanceId: _getOrCreateInstanceId(
                selectedTopic.topicId!,
                existingInstanceId: selectedTopic.instanceId,
              ),
              initialTitle: selectedTopic.initialTitle,
              scrollToPostNumber: selectedTopic.scrollToPostNumber,
            )
          : null,
      masterFloatingActionButton: user != null
          ? _TopicsFab(
              onCreateTopic: () => _createTopic(context, ref),
            )
          : null,
    );
  }

  Future<void> _createTopic(BuildContext context, WidgetRef ref) async {
    final categoryId = ref.read(currentTabCategoryIdProvider);
    final tags = ref.read(tabTagsProvider(categoryId));
    final topicId = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => CreateTopicPage(
        initialCategoryId: categoryId,
        initialTags: tags.isNotEmpty ? tags : null,
      )),
    );
    if (topicId != null && context.mounted) {
      // 刷新当前 tab 的列表
      ref.invalidate(topicListProvider(null));
      // 在 Master-Detail 模式下，选中新话题
      ref.read(selectedTopicProvider.notifier).select(topicId: topicId);
    }
  }
}

/// 首页 FAB：向上滚动时切换为刷新按钮
class _TopicsFab extends ConsumerWidget {
  const _TopicsFab({required this.onCreateTopic});

  final VoidCallback onCreateTopic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showRefresh = ref.watch(fabRefreshModeProvider);

    return FloatingActionButton(
      heroTag: 'createTopic',
      onPressed: showRefresh ? () => _refreshTopics(ref) : onCreateTopic,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          showRefresh ? Icons.refresh : Icons.add,
          key: ValueKey(showRefresh),
        ),
      ),
    );
  }

  void _refreshTopics(WidgetRef ref) {
    ref.read(fabRefreshModeProvider.notifier).state = false;
    ref.read(scrollToTopProvider.notifier).trigger();
    ref.read(fabRefreshSignalProvider.notifier).trigger();
  }
}

/// 话题详情面板（用于双栏模式，不包含返回按钮）
class TopicDetailPane extends ConsumerWidget {
  const TopicDetailPane({
    super.key,
    required this.topicId,
    this.instanceId,
    this.initialTitle,
    this.scrollToPostNumber,
  });

  final int topicId;
  final String? instanceId;
  final String? initialTitle;
  final int? scrollToPostNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TopicDetailPage(
      topicId: topicId,
      instanceId: instanceId,
      initialTitle: initialTitle,
      scrollToPostNumber: scrollToPostNumber,
      embeddedMode: true, // 嵌入模式，不显示返回按钮
    );
  }
}
