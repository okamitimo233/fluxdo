import '../utils/time_utils.dart';
import '../utils/url_helper.dart';

/// Discourse 通知类型枚举
enum NotificationType {
  mentioned(1, '提及'),
  replied(2, '回复'),
  quoted(3, '引用'),
  edited(4, '编辑'),
  liked(5, '点赞'),
  privateMessage(6, '私信'),
  invitedToPrivateMessage(7, '私信邀请'),
  inviteeAccepted(8, '邀请已接受'),
  posted(9, '发帖'),
  movedPost(10, '帖子移动'),
  linked(11, '链接'),
  grantedBadge(12, '获得徽章'),
  invitedToTopic(13, '话题邀请'),
  custom(14, '自定义'),
  groupMentioned(15, '群组提及'),
  groupMessageSummary(16, '群组消息摘要'),
  watchingFirstPost(17, '关注首帖'),
  topicReminder(18, '话题提醒'),
  likedConsolidated(19, '点赞汇总'),
  postApproved(20, '帖子已批准'),
  codeReviewCommitApproved(21, '代码审核通过'),
  membershipRequestAccepted(22, '成员申请已接受'),
  membershipRequestConsolidated(23, '成员申请汇总'),
  bookmarkReminder(24, '书签提醒'),
  reaction(25, '反应'),
  votesReleased(26, '投票发布'),
  eventReminder(27, '活动提醒'),
  eventInvitation(28, '活动邀请'),
  chatMention(29, '聊天提及'),
  chatMessage(30, '聊天消息'),
  chatInvitation(31, '聊天邀请'),
  chatGroupMention(32, '群聊提及'),
  chatQuotedPost(33, '聊天引用'),
  assignedTopic(34, '话题指派'),
  questionAnswerUserCommented(35, '问答评论'),
  watchingCategoryOrTag(36, '关注分类或标签'),
  newFeatures(37, '新功能'),
  adminProblems(38, '管理员问题'),
  linkedConsolidated(39, '链接汇总'),
  chatWatchedThread(40, '聊天关注话题'),
  following(800, '关注'),
  followingCreatedTopic(801, '关注的用户创建了话题'),
  followingReplied(802, '关注的用户回复了'),
  circlesActivity(900, '圈子活动'),
  unknown(0, '未知');

  final int id;
  final String label;
  const NotificationType(this.id, this.label);

  static NotificationType fromId(int id) {
    return NotificationType.values.firstWhere(
      (type) => type.id == id,
      orElse: () => NotificationType.unknown,
    );
  }
}

/// 通知详细数据
class NotificationData {
  final String? displayUsername;
  final String? originalPostId;
  final int? originalPostType;
  final String? originalUsername;
  final int? revisionNumber;
  final String? topicTitle;
  final String? badgeName;
  final int? badgeId;
  final String? badgeSlug;
  final String? groupName;
  final String? inboxCount;
  final int? count;
  final String? username;
  final String? username2;
  final String? avatarTemplate;

  NotificationData({
    this.displayUsername,
    this.originalPostId,
    this.originalPostType,
    this.originalUsername,
    this.revisionNumber,
    this.topicTitle,
    this.badgeName,
    this.badgeId,
    this.badgeSlug,
    this.groupName,
    this.inboxCount,
    this.count,
    this.username,
    this.username2,
    this.avatarTemplate,
  });

  factory NotificationData.fromJson(Map<String, dynamic> json) {
    return NotificationData(
      displayUsername: json['display_username'] as String?,
      originalPostId: json['original_post_id']?.toString(),
      originalPostType: json['original_post_type'] as int?,
      originalUsername: json['original_username'] as String?,
      revisionNumber: json['revision_number'] as int?,
      topicTitle: json['topic_title'] as String?,
      badgeName: json['badge_name'] as String?,
      badgeId: json['badge_id'] as int?,
      badgeSlug: json['badge_slug'] as String?,
      groupName: json['group_name'] as String?,
      inboxCount: json['inbox_count']?.toString(),
      count: json['count'] as int?,
      username: json['username'] as String?,
      username2: json['username2'] as String?,
      avatarTemplate: json['acting_user_avatar_template'] as String? ?? json['avatar_template'] as String?,
    );
  }
}

/// Discourse 通知模型
class DiscourseNotification {
  final int id;
  final int userId;
  final NotificationType notificationType;
  final bool read;
  final bool highPriority;
  final DateTime createdAt;
  final int? postNumber;
  final int? topicId;
  final String? slug;
  final NotificationData data;
  final String? fancyTitle;
  final String? actingUserAvatarTemplate;

  DiscourseNotification({
    required this.id,
    required this.userId,
    required this.notificationType,
    required this.read,
    required this.highPriority,
    required this.createdAt,
    this.postNumber,
    this.topicId,
    this.slug,
    required this.data,
    this.fancyTitle,
    this.actingUserAvatarTemplate,
  });

  factory DiscourseNotification.fromJson(Map<String, dynamic> json) {
    return DiscourseNotification(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      notificationType: NotificationType.fromId(json['notification_type'] as int),
      read: json['read'] as bool? ?? false,
      highPriority: json['high_priority'] as bool? ?? false,
      createdAt: TimeUtils.parseUtcTime(json['created_at'] as String?) ?? DateTime.now(),
      postNumber: json['post_number'] as int?,
      topicId: json['topic_id'] as int?,
      slug: json['slug'] as String?,
      data: NotificationData.fromJson(json['data'] as Map<String, dynamic>? ?? {}),
      fancyTitle: json['fancy_title'] as String?,
      actingUserAvatarTemplate: json['acting_user_avatar_template'] as String?,
    );
  }

  /// 获取显示用户名
  String? get username {
    return data.displayUsername ?? data.username ?? data.originalUsername;
  }

  /// 获取头像 URL
  String getAvatarUrl({int size = 96}) {
    // 优先使用顶层的 acting_user_avatar_template
    String? template = actingUserAvatarTemplate ?? data.avatarTemplate;
    if (template == null || template.isEmpty) {
      return '';
    }
    // 替换 {size} 占位符并解析 URL
    final url = template.replaceAll('{size}', size.toString());
    return UrlHelper.resolveUrl(url);
  }

  DiscourseNotification copyWith({
    int? id,
    int? userId,
    NotificationType? notificationType,
    bool? read,
    bool? highPriority,
    DateTime? createdAt,
    int? postNumber,
    int? topicId,
    String? slug,
    NotificationData? data,
    String? fancyTitle,
    String? actingUserAvatarTemplate,
  }) {
    return DiscourseNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      notificationType: notificationType ?? this.notificationType,
      read: read ?? this.read,
      highPriority: highPriority ?? this.highPriority,
      createdAt: createdAt ?? this.createdAt,
      postNumber: postNumber ?? this.postNumber,
      topicId: topicId ?? this.topicId,
      slug: slug ?? this.slug,
      data: data ?? this.data,
      fancyTitle: fancyTitle ?? this.fancyTitle,
      actingUserAvatarTemplate: actingUserAvatarTemplate ?? this.actingUserAvatarTemplate,
    );
  }

  /// 获取通知标题
  String get title {
    final displayName = data.displayUsername ?? data.originalUsername ?? '';

    // 某些类型有专门的标题逻辑，不应使用话题标题
    switch (notificationType) {
      case NotificationType.grantedBadge:
        return data.badgeName != null
            ? "获得了 '${data.badgeName}'"
            : notificationType.label;
      case NotificationType.inviteeAccepted:
        return displayName.isNotEmpty ? '$displayName 接受了你的邀请' : notificationType.label;
      case NotificationType.following:
        return displayName.isNotEmpty ? '$displayName 开始关注你' : notificationType.label;
      case NotificationType.likedConsolidated:
        final count = data.count ?? 0;
        return displayName.isNotEmpty
            ? '$displayName 点赞了你的 $count 个帖子'
            : '$count 人赞了你的帖子';
      case NotificationType.linkedConsolidated:
        final count = data.count ?? 0;
        return displayName.isNotEmpty
            ? '$displayName 链接了你的 $count 个帖子'
            : '$count 人链接了你的帖子';
      case NotificationType.groupMessageSummary:
        final count = data.inboxCount ?? '0';
        return '${data.groupName ?? ""} 收件箱有 $count 条消息';
      case NotificationType.membershipRequestAccepted:
        return "加入 '${data.groupName ?? ""}' 的申请已被接受";
      case NotificationType.membershipRequestConsolidated:
        final count = data.count ?? 0;
        return "$count 个未处理的 '${data.groupName ?? ""}' 成员申请";
      case NotificationType.newFeatures:
        return '有新功能可用！';
      case NotificationType.adminProblems:
        return '网站信息中心有新建议';
      default:
        break;
    }

    // 话题类通知：使用话题标题
    if (data.topicTitle != null && data.topicTitle!.isNotEmpty) return data.topicTitle!;
    if (fancyTitle != null && fancyTitle!.isNotEmpty) return fancyTitle!;

    // 兜底使用通知类型
    return notificationType.label;
  }

  /// 获取通知描述
  String get description {
    final username = data.displayUsername ?? data.originalUsername ?? '';
    switch (notificationType) {
      // === 话题类通知：描述为 "用户 + 操作" ===
      case NotificationType.mentioned:
        return '$username 在帖子中提及了你';
      case NotificationType.replied:
        return '$username 回复了你的帖子';
      case NotificationType.quoted:
        return '$username 引用了你的帖子';
      case NotificationType.liked:
        // 处理多人点赞
        final count = data.count ?? 1;
        if (count <= 1) {
          return '$username 赞了你的帖子';
        } else if (count == 2) {
          final username2 = data.username2 ?? '';
          return '$username、$username2 赞了你的帖子';
        } else {
          return '$username 和其他 ${count - 1} 人赞了你的帖子';
        }
      case NotificationType.privateMessage:
        return '$username 发送了私信';
      case NotificationType.posted:
        return '$username 发布了新帖子';
      case NotificationType.linked:
        return '$username 链接了你的帖子';
      case NotificationType.edited:
        return '$username 编辑了帖子';
      case NotificationType.movedPost:
        return '$username 移动了帖子';
      case NotificationType.groupMentioned:
        return '$username @${data.groupName ?? ""}';
      case NotificationType.watchingFirstPost:
        return '新建话题';
      case NotificationType.followingCreatedTopic:
        return '$username 创建了新话题';
      case NotificationType.followingReplied:
        return '$username 回复了话题';
      case NotificationType.invitedToTopic:
        return '$username 邀请你参与话题';
      case NotificationType.invitedToPrivateMessage:
        return '$username 邀请你参与私信';
      case NotificationType.bookmarkReminder:
        return '书签提醒';
      case NotificationType.topicReminder:
        return '话题提醒';
      case NotificationType.reaction:
        return '$username 对你的帖子做出了反应';
      case NotificationType.votesReleased:
        return '投票已发布';
      case NotificationType.eventReminder:
        return '活动提醒';
      case NotificationType.eventInvitation:
        return '$username 邀请你参加活动';
      case NotificationType.chatMention:
        return '$username 在聊天中提及了你';
      case NotificationType.chatMessage:
        return '$username 发送了聊天消息';
      case NotificationType.chatInvitation:
        return '$username 邀请你参与聊天';
      case NotificationType.chatGroupMention:
        return '群组在聊天中被提及';
      case NotificationType.chatQuotedPost:
        return '$username 在聊天中引用了你';
      case NotificationType.chatWatchedThread:
        return '你关注的聊天话题有新消息';
      case NotificationType.assignedTopic:
        return '话题已分配给你';
      case NotificationType.questionAnswerUserCommented:
        return '$username 评论了问答';
      case NotificationType.watchingCategoryOrTag:
        return '$username 发布了新帖子';
      case NotificationType.postApproved:
        return '你的帖子已被批准';
      case NotificationType.codeReviewCommitApproved:
        return '代码审核已通过';
      case NotificationType.custom:
        return '自定义通知';
      case NotificationType.circlesActivity:
        return '圈子有新动态';

      // === 非话题类通知：标题已包含完整信息，描述使用类型标签 ===
      case NotificationType.grantedBadge:
      case NotificationType.inviteeAccepted:
      case NotificationType.following:
      case NotificationType.likedConsolidated:
      case NotificationType.linkedConsolidated:
      case NotificationType.groupMessageSummary:
      case NotificationType.membershipRequestAccepted:
      case NotificationType.membershipRequestConsolidated:
      case NotificationType.newFeatures:
      case NotificationType.adminProblems:
        return notificationType.label;

      default:
        if (username.isNotEmpty) return username;
        return notificationType.label;
    }
  }
}

/// 通知列表响应
class NotificationListResponse {
  final List<DiscourseNotification> notifications;
  final int totalRowsNotifications;
  final int seenNotificationId;
  final String? loadMoreNotifications;

  NotificationListResponse({
    required this.notifications,
    required this.totalRowsNotifications,
    required this.seenNotificationId,
    this.loadMoreNotifications,
  });

  factory NotificationListResponse.fromJson(Map<String, dynamic> json) {
    final notificationsList = json['notifications'] as List<dynamic>? ?? [];
    return NotificationListResponse(
      notifications: notificationsList
          .map((e) => DiscourseNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalRowsNotifications: json['total_rows_notifications'] as int? ?? 0,
      seenNotificationId: json['seen_notification_id'] as int? ?? 0,
      loadMoreNotifications: json['load_more_notifications'] as String?,
    );
  }
}
