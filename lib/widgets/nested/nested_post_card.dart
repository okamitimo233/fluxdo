import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/s.dart';
import '../../models/nested_topic.dart';
import '../../models/topic.dart';
import '../../providers/nested_topic_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/topic_session_provider.dart';
import '../../pages/user_profile_page.dart';
import '../../utils/time_utils.dart';
import '../content/discourse_html_content/chunked/chunked_html_content.dart';
import '../post/post_item/widgets/post_footer_section/post_footer_section.dart';
import 'nested_collapsed_bar.dart';
import 'nested_post_gutter.dart';

// 布局常量
const double _avatarSize = NestedPostAvatar.size;
const double _columnGap = 8.0;
const double _verticalGap = 6.0;
const double _lineWidth = 2.0;
const double _lineCenterX = _avatarSize / 2; // 竖线 X 中心（相对于帖子左边缘）

/// 嵌套帖子卡片
///
/// 布局：无 IntrinsicHeight，用 Stack 叠加竖线
/// ```
/// Stack
/// ├── 竖线（Positioned: top=avatar底 bottom=0，如果有子节点且展开）
/// ├── L 连接线（CustomPaint，如果 depth > 0）
/// ├── 兄弟延续线（Positioned，如果不是最后一个子节点）
/// └── Column（自然高度）
///     ├── Row: [avatar] [gap] [content / collapsed_bar]
///     └── children（缩进）
/// ```
class NestedPostCard extends ConsumerStatefulWidget {
  final NestedNode node;
  final int topicId;
  final TopicDetail detail;
  final NestedTopicParams params;
  final int depth;
  final bool isLastChild;
  final bool isLoggedIn;
  final void Function(Post? replyToPost) onReply;
  final void Function(Post post) onEdit;
  final void Function(int postId) onRefreshPost;
  final void Function(int postNumber) onJumpToPost;
  final void Function(int postId, bool accepted)? onSolutionChanged;
  /// 父节点竖线是否高亮
  final bool parentLineHighlighted;
  /// 展开/折叠状态存储（跨滚动回收保持状态）
  final Map<int, bool>? expansionState;

  const NestedPostCard({
    super.key,
    required this.node,
    required this.topicId,
    required this.detail,
    required this.params,
    required this.depth,
    this.isLastChild = false,
    required this.isLoggedIn,
    required this.onReply,
    required this.onEdit,
    required this.onRefreshPost,
    required this.onJumpToPost,
    this.onSolutionChanged,
    this.parentLineHighlighted = false,
    this.expansionState,
  });

  @override
  ConsumerState<NestedPostCard> createState() => _NestedPostCardState();
}

class _NestedPostCardState extends ConsumerState<NestedPostCard> {
  late bool _expanded;
  late bool _collapsed;
  late List<NestedNode> _children;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  bool _depthLineHovered = false;

  @override
  void initState() {
    super.initState();
    _children = List.from(widget.node.children);
    _hasMore = widget.node.hasMoreChildren;

    // 从状态存储恢复，否则有预加载子节点就展开
    final cached = widget.expansionState?[widget.node.post.postNumber];
    if (cached != null) {
      _expanded = cached;
      _collapsed = !cached && _hasReplies;
    } else {
      _expanded = _children.isNotEmpty;
      _collapsed = false;
    }
  }

  bool get _hasReplies => widget.node.directReplyCount > 0 || _children.isNotEmpty;
  bool get _showDepthLine => _hasReplies && !_collapsed;

  int get _replyCount {
    final c = widget.node.totalDescendantCount > 0
        ? widget.node.totalDescendantCount
        : widget.node.directReplyCount;
    return c > 0 ? c : _children.length;
  }

  void _toggleExpanded() {
    setState(() {
      if (_expanded) {
        _expanded = false;
        _collapsed = true;
        _depthLineHovered = false;
      } else {
        _expanded = true;
        _collapsed = false;
        if (_children.isEmpty && widget.node.directReplyCount > 0) {
          _loadChildren();
        }
      }
      // 持久化到状态存储
      widget.expansionState?[widget.node.post.postNumber] = _expanded;
    });
  }

  Future<void> _loadChildren() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final notifier = ref.read(nestedTopicProvider(widget.params).notifier);
      final response = await notifier.loadChildren(
        widget.node.post.postNumber,
        page: _page,
        depth: widget.depth + 1,
      );
      if (!mounted) return;
      setState(() {
        _children.addAll(response.children);
        _hasMore = response.hasMore;
        _page = response.page + 1;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = widget.node.post;
    final isRoot = widget.depth == 0;

    // 线条颜色
    final defaultLineColor = theme.colorScheme.outlineVariant;
    final highlightColor = theme.colorScheme.primary;
    final depthLineColor = _depthLineHovered ? highlightColor : defaultLineColor;
    final connectorColor = widget.parentLineHighlighted ? highlightColor : defaultLineColor;

    // 帖子内容列
    final Widget contentColumn = _collapsed
        ? NestedCollapsedBar(
            username: post.username,
            replyCount: _replyCount,
            onTap: _toggleExpanded,
          )
        : _buildArticle(theme, post);

    // 主体行 + 视觉竖线（IgnorePointer，仅绘制，不处理事件）
    Widget mainRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NestedPostAvatar(avatarTemplate: post.avatarTemplate, username: post.username),
        const SizedBox(width: _columnGap),
        Expanded(child: contentColumn),
      ],
    );
    if (_showDepthLine) {
      mainRow = Stack(
        children: [
          mainRow,
          // 视觉竖线 + ⊖ 图标（仅绘制，不拦截事件）
          Positioned(
            left: _lineCenterX - 8,
            top: _avatarSize + 4,
            bottom: 0,
            child: IgnorePointer(
              child: SizedBox(
                width: 16,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(child: Container(width: _lineWidth, color: depthLineColor)),
                    if (_expanded)
                      Positioned(
                        bottom: 0,
                        child: Container(
                          width: 16, height: 16,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.surface),
                          child: Icon(Icons.remove_circle_outline, size: 14, color: depthLineColor),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 子节点
    final bool showChildren = _expanded && !_collapsed &&
        (_children.isNotEmpty || _isLoadingMore || _hasMore);
    final bool showExpandBtn = !_expanded && !_collapsed && _hasReplies;

    Widget card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        mainRow,
        if (showChildren)
          Padding(
            padding: const EdgeInsets.only(left: _avatarSize + _columnGap),
            child: _buildChildren(theme),
          ),
        if (showExpandBtn)
          Padding(
            padding: const EdgeInsets.only(left: _avatarSize + _columnGap, top: 4, bottom: 4),
            child: _buildExpandButton(theme),
          ),
      ],
    );

    // 外层 Stack：透明交互区 + L 连接线 + 兄弟延续线
    final bool needsStack = _showDepthLine || !isRoot;
    if (needsStack) {
      card = Stack(
        clipBehavior: Clip.none,
        children: [
          card,

          // 竖线交互区（覆盖整个 gutter 宽度，包括子节点 L 弯的横线区域）
          if (_showDepthLine)
            Positioned(
              left: 0,
              top: _avatarSize + 4,
              bottom: 0,
              child: MouseRegion(
                onEnter: (_) => setState(() => _depthLineHovered = true),
                onExit: (_) => setState(() => _depthLineHovered = false),
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _toggleExpanded,
                  behavior: HitTestBehavior.translucent,
                  child: SizedBox(width: _avatarSize + _columnGap),
                ),
              ),
            ),

          // L 形连接线（纯视觉）
          if (!isRoot)
            Positioned(
              left: -(_columnGap + _lineCenterX) - _lineWidth / 2,
              top: -_verticalGap,
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(_lineCenterX + _columnGap + _lineWidth / 2, _verticalGap + _avatarSize / 2),
                  painter: _LConnectorPainter(color: connectorColor),
                ),
              ),
            ),

          // 兄弟延续线（纯视觉）
          if (!isRoot && !widget.isLastChild)
            Positioned(
              left: -(_columnGap + _lineCenterX) - _lineWidth / 2,
              top: -_verticalGap,
              bottom: 0,
              width: _lineWidth,
              child: IgnorePointer(child: ColoredBox(color: connectorColor)),
            ),
        ],
      );
    }

    // 非根帖子添加顶部间距（padding 在 Stack 外面！）
    if (!isRoot) {
      card = Padding(
        padding: const EdgeInsets.only(top: _verticalGap),
        child: card,
      );
    }

    // 根帖子底部分隔
    if (isRoot) {
      card = Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: card,
      );
    }

    return card;
  }

  /// 帖子文章区
  Widget _buildArticle(ThemeData theme, Post post) {
    final isOp = widget.detail.createdBy?.username == post.username;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        _buildHeader(theme, post, isOp),
        const SizedBox(height: 4),
        // Content
        ChunkedHtmlContent(
          html: post.cooked,
          textStyle: theme.textTheme.bodyMedium?.copyWith(
            height: 1.5,
            fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) *
                ref.watch(preferencesProvider).contentFontScale,
          ),
          post: post,
          topicId: widget.topicId,
        ),
        // 完整操作栏（复用 PostFooterSection，隐藏回复展开按钮）
        PostFooterSection(
          post: post,
          topicId: widget.topicId,
          topicHasAcceptedAnswer: widget.detail.hasAcceptedAnswer,
          acceptedAnswerPostNumber: widget.detail.acceptedAnswerPostNumber,
          padding: const EdgeInsets.only(top: 4),
          onReply: widget.isLoggedIn ? () => widget.onReply(post) : null,
          onEdit: widget.isLoggedIn && post.canEdit ? () => widget.onEdit(post) : null,
          onShareAsImage: null,
          onRefreshPost: widget.onRefreshPost,
          onJumpToPost: widget.onJumpToPost,
          onSolutionChanged: widget.onSolutionChanged,
          hideRepliesButton: true,
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, Post post, bool isOp) {
    return Row(
      children: [
        // 用户名（可点击）
        GestureDetector(
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => UserProfilePage(username: post.username))),
          child: Text(post.username, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        if (isOp) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('OP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
          ),
        ],
        if (post.replyToPostNumber > 0 && post.replyToUser != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.subdirectory_arrow_right, size: 12, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(width: 2),
          Text(post.replyToUser!.username, style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          )),
        ],
        const Spacer(),
        // 时间 + 未读蓝点（蓝点在时间右上角，和 PostItem 一致）
        Consumer(
          builder: (context, ref, _) {
            final sessionState = ref.watch(topicSessionProvider(widget.topicId));
            final isNew = !post.read;
            final isReadInSession = sessionState.readPostNumbers.contains(post.postNumber);
            final showDot = isNew && !isReadInSession;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Text(TimeUtils.formatRelativeTime(post.createdAt), style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 11,
                )),
                Positioned(
                  right: -6,
                  top: -2,
                  child: AnimatedOpacity(
                    opacity: showDot ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    child: Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.surface, width: 1),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildExpandButton(ThemeData theme) {
    return GestureDetector(
      onTap: _toggleExpanded,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_circle_outline, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text(context.l10n.nested_repliesCount(_replyCount), style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary, fontWeight: FontWeight.w500,
          )),
        ],
      ),
    );
  }

  Widget _buildChildren(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < _children.length; i++)
          NestedPostCard(
            node: _children[i],
            topicId: widget.topicId,
            detail: widget.detail,
            params: widget.params,
            depth: widget.depth + 1,
            isLastChild: i == _children.length - 1 && !_hasMore,
            isLoggedIn: widget.isLoggedIn,
            onReply: widget.onReply,
            onEdit: widget.onEdit,
            onRefreshPost: widget.onRefreshPost,
            onJumpToPost: widget.onJumpToPost,
            onSolutionChanged: widget.onSolutionChanged,
            parentLineHighlighted: _depthLineHovered,
            expansionState: widget.expansionState,
          ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _isLoadingMore
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : GestureDetector(
                    onTap: _loadChildren,
                    child: Text(context.l10n.nested_loadMoreReplies,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                  ),
          ),
      ],
    );
  }
}

/// L 形连接线（从父竖线向右弯到子头像）
class _LConnectorPainter extends CustomPainter {
  final Color color;
  _LConnectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lineWidth
      ..strokeCap = StrokeCap.butt;

    const radius = 8.0;
    // 起点在左上，终点在右下
    // 从 (lineWidth/2, 0) 垂直向下，弯角后水平向右到 (size.width, size.height)
    final x = _lineWidth / 2;
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x, size.height - radius)
      ..arcToPoint(
        Offset(x + radius, size.height),
        radius: const Radius.circular(radius),
        clockwise: false,
      )
      ..lineTo(size.width, size.height);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LConnectorPainter old) => color != old.color;
}
