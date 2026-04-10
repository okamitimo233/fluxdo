import 'topic.dart';

/// 树形节点：帖子 + 预加载的子节点
class NestedNode {
  final Post post;
  final List<NestedNode> children;
  final int directReplyCount;
  final int totalDescendantCount;

  const NestedNode({
    required this.post,
    this.children = const [],
    this.directReplyCount = 0,
    this.totalDescendantCount = 0,
  });

  factory NestedNode.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['children'] as List<dynamic>? ?? [];
    return NestedNode(
      post: Post.fromJson(json),
      children: childrenJson
          .map((e) => NestedNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      directReplyCount: json['direct_reply_count'] as int? ?? 0,
      totalDescendantCount: json['total_descendant_count'] as int? ?? 0,
    );
  }

  /// 是否有未加载的子回复
  bool get hasMoreChildren => directReplyCount > children.length;

  NestedNode copyWith({
    Post? post,
    List<NestedNode>? children,
    int? directReplyCount,
    int? totalDescendantCount,
  }) {
    return NestedNode(
      post: post ?? this.post,
      children: children ?? this.children,
      directReplyCount: directReplyCount ?? this.directReplyCount,
      totalDescendantCount: totalDescendantCount ?? this.totalDescendantCount,
    );
  }
}

/// 根帖子列表 API 响应
class NestedRootsResponse {
  final Map<String, dynamic>? topicJson; // page=0 时有话题元数据
  final Post? opPost;
  final String? sort;
  final List<NestedNode> roots;
  final bool hasMoreRoots;
  final int page;
  final List<int>? pinnedPostIds;

  const NestedRootsResponse({
    this.topicJson,
    this.opPost,
    this.sort,
    required this.roots,
    required this.hasMoreRoots,
    required this.page,
    this.pinnedPostIds,
  });

  factory NestedRootsResponse.fromJson(Map<String, dynamic> json) {
    final rootsJson = json['roots'] as List<dynamic>? ?? [];
    final opPostJson = json['op_post'] as Map<String, dynamic>?;
    final pinnedJson = json['pinned_post_ids'] as List<dynamic>?;

    return NestedRootsResponse(
      topicJson: json['topic'] as Map<String, dynamic>?,
      opPost: opPostJson != null ? Post.fromJson(opPostJson) : null,
      sort: json['sort'] as String?,
      roots: rootsJson
          .map((e) => NestedNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMoreRoots: json['has_more_roots'] as bool? ?? false,
      page: json['page'] as int? ?? 0,
      pinnedPostIds: pinnedJson?.map((e) => e as int).toList(),
    );
  }
}

/// 子回复 API 响应
class NestedChildrenResponse {
  final List<NestedNode> children;
  final bool hasMore;
  final int page;

  const NestedChildrenResponse({
    required this.children,
    required this.hasMore,
    required this.page,
  });

  factory NestedChildrenResponse.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['children'] as List<dynamic>? ?? [];
    return NestedChildrenResponse(
      children: childrenJson
          .map((e) => NestedNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: json['has_more'] as bool? ?? false,
      page: json['page'] as int? ?? 0,
    );
  }
}
