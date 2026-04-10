part of 'discourse_service.dart';

/// 嵌套视图（树形话题）相关 API
mixin _NestedMixin on _DiscourseServiceBase {
  /// 获取根帖子列表
  /// GET /nested/topic/:topic_id/roots.json?sort=old&page=0
  Future<NestedRootsResponse> getNestedRoots(
    int topicId, {
    String sort = 'old',
    int page = 0,
  }) async {
    final response = await _dio.get(
      '/nested/topic/$topicId/roots.json',
      queryParameters: {
        'sort': sort,
        'page': page,
      },
    );
    return NestedRootsResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// 获取子回复
  /// GET /nested/topic/:topic_id/children/:postNumber.json?sort=old&page=0&depth=1
  Future<NestedChildrenResponse> getNestedChildren(
    int topicId,
    int postNumber, {
    String sort = 'old',
    int page = 0,
    int depth = 1,
  }) async {
    final response = await _dio.get(
      '/nested/topic/$topicId/children/$postNumber.json',
      queryParameters: {
        'sort': sort,
        'page': page,
        'depth': depth,
      },
    );
    return NestedChildrenResponse.fromJson(response.data as Map<String, dynamic>);
  }
}
