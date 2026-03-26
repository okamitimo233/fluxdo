/// Directory API 统计模型
/// 端点：/directory_items.json?period=xxx&username=yyy
class DirectoryItem {
  final int likesReceived;
  final int likesGiven;
  final int topicsEntered;
  final int topicCount;
  final int postCount;
  final int postsRead;
  final int daysVisited;
  final int? timeRead; // 仅 period=all 时有值

  const DirectoryItem({
    this.likesReceived = 0,
    this.likesGiven = 0,
    this.topicsEntered = 0,
    this.topicCount = 0,
    this.postCount = 0,
    this.postsRead = 0,
    this.daysVisited = 0,
    this.timeRead,
  });

  factory DirectoryItem.fromJson(Map<String, dynamic> json) {
    return DirectoryItem(
      likesReceived: json['likes_received'] as int? ?? 0,
      likesGiven: json['likes_given'] as int? ?? 0,
      topicsEntered: json['topics_entered'] as int? ?? 0,
      topicCount: json['topic_count'] as int? ?? 0,
      postCount: json['post_count'] as int? ?? 0,
      postsRead: json['posts_count'] as int? ?? 0,
      daysVisited: json['days_visited'] as int? ?? 0,
      timeRead: json['time_read'] as int?,
    );
  }
}
