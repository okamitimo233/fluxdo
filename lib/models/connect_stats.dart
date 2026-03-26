import 'package:html/parser.dart' as html_parser;

/// connect.linux.do 信任等级周期统计模型
class ConnectStats {
  final int daysVisited;
  final int topicsRepliedTo; // 独有：回复主题数
  final int topicsViewed;
  final int postsRead;
  final int likesGiven;
  final int likesReceived;
  final int likesReceivedDays; // 独有：获赞天数
  final int likesReceivedUsers; // 独有：获赞人数
  final int timePeriod; // 时间周期（天数）

  const ConnectStats({
    this.daysVisited = 0,
    this.topicsRepliedTo = 0,
    this.topicsViewed = 0,
    this.postsRead = 0,
    this.likesGiven = 0,
    this.likesReceived = 0,
    this.likesReceivedDays = 0,
    this.likesReceivedUsers = 0,
    this.timePeriod = 100,
  });

  /// 从 connect.linux.do HTML 解析
  factory ConnectStats.fromHtml(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final cardDiv = document.querySelector('div.card');
    if (cardDiv == null) {
      throw Exception('未找到统计卡片');
    }

    // 从 ring 圈获取：访问天数 / 回复主题数 / 浏览话题
    final rings = cardDiv.querySelectorAll('.tl3-ring');
    int daysVisited = 0;
    int topicsRepliedTo = 0;
    int topicsViewed = 0;

    for (final ring in rings) {
      final label = ring.querySelector('.tl3-ring-label')?.text.trim() ?? '';
      final circle = ring.querySelector('.tl3-ring-circle');
      final style = circle?.attributes['style'] ?? '';
      final val = _parseCssVar(style, '--val').toInt();

      if (label.contains('访问天数') || label.contains('days visited')) {
        daysVisited = val;
      } else if (label.contains('回复主题') || label.contains('topics replied')) {
        topicsRepliedTo = val;
      } else if (label.contains('浏览话题') || label.contains('topics viewed')) {
        topicsViewed = val;
      }
    }

    // 从 bar 条获取：已读帖子 / 送赞 / 获赞 / 获赞天数 / 获赞人数
    final bars = cardDiv.querySelectorAll('.tl3-bar-item');
    int postsRead = 0;
    int likesGiven = 0;
    int likesReceived = 0;
    int likesReceivedDays = 0;
    int likesReceivedUsers = 0;

    for (final bar in bars) {
      final label = bar.querySelector('.tl3-bar-label')?.text.trim() ?? '';
      final fill = bar.querySelector('.tl3-bar-fill');
      final style = fill?.attributes['style'] ?? '';
      final val = _parseCssVar(style, '--val').toInt();

      if (label.contains('已读帖子') || label.contains('posts read')) {
        postsRead = val;
      } else if (label.contains('送赞') || label.contains('likes given')) {
        likesGiven = val;
      } else if (label.contains('获赞天数') || label.contains('liked days')) {
        likesReceivedDays = val;
      } else if (label.contains('获赞人数') || label.contains('liked users')) {
        likesReceivedUsers = val;
      } else if (label.contains('获赞') || label.contains('likes received')) {
        likesReceived = val;
      }
    }

    // 从副标题解析时间周期
    int timePeriod = 100;
    final subtitle = cardDiv.querySelector('.card-subtitle')?.text.trim() ?? '';
    final periodMatch = RegExp(r'(\d+)\s*[天days]').firstMatch(subtitle);
    if (periodMatch != null) {
      timePeriod = int.tryParse(periodMatch.group(1) ?? '100') ?? 100;
    }

    return ConnectStats(
      daysVisited: daysVisited,
      topicsRepliedTo: topicsRepliedTo,
      topicsViewed: topicsViewed,
      postsRead: postsRead,
      likesGiven: likesGiven,
      likesReceived: likesReceived,
      likesReceivedDays: likesReceivedDays,
      likesReceivedUsers: likesReceivedUsers,
      timePeriod: timePeriod,
    );
  }

  static double _parseCssVar(String style, String varName) {
    final regex = RegExp('$varName:\\s*([0-9.]+)');
    final match = regex.firstMatch(style);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }
}
