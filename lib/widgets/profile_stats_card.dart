import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile_stats_config.dart';
import '../models/user.dart';
import '../models/directory_item.dart';
import '../models/connect_stats.dart';
import '../providers/core_providers.dart';
import '../providers/directory_providers.dart';
import '../providers/profile_stats_provider.dart';
import '../utils/number_utils.dart';
import '../l10n/s.dart';

/// 统计卡片渲染组件（个人页使用）
///
/// [statsCardKey] 可选，外部传入 GlobalKey 用于引导高亮定位。
class ProfileStatsCard extends ConsumerWidget {
  final VoidCallback? onEdit;
  final GlobalKey? statsCardKey;

  const ProfileStatsCard({super.key, this.onEdit, this.statsCardKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(profileStatsConfigProvider);
    final theme = Theme.of(context);

    // 空状态：显示占位卡片，引导用户添加
    if (config.enabledStats.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_chart_rounded,
                  size: 20,
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Text(
                  S.current.profileStats_addItems,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return KeyedSubtree(
      key: statsCardKey,
      child: _StatsCardContent(
        config: config,
        onEdit: onEdit,
      ),
    );
  }
}

/// 仅预览用（不读取 provider 配置，直接传入数据）
class ProfileStatsCardPreview extends StatelessWidget {
  final ProfileStatsConfig config;
  final Map<ProfileStatType, int> values;
  final VoidCallback? onTap;

  const ProfileStatsCardPreview({
    super.key,
    required this.config,
    required this.values,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (config.enabledStats.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                S.current.profileStats_noItemsSelected,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            children: [
              _buildLayout(context),
              // 数据源标签
              if (config.dataSource != StatsDataSource.summary) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        getDataSourceLabel(config.dataSource),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayout(BuildContext context) {
    final items = config.enabledStats.map((stat) {
      final value = values[stat] ?? 0;
      return _StatItemData(
        value: _formatValue(stat, value),
        label: getStatLabel(stat),
        rawValue: value,
        isTimeValue: stat == ProfileStatType.timeRead ||
            stat == ProfileStatType.recentTimeRead,
      );
    }).toList();

    if (config.layoutMode == StatsLayoutMode.scroll) {
      return _buildScrollLayout(context, items);
    }
    return _buildGridLayout(context, items);
  }

  Widget _buildGridLayout(BuildContext context, List<_StatItemData> items) {
    final theme = Theme.of(context);
    final columns = config.columnsPerRow;

    // 按行分组
    final List<List<_StatItemData>> rows = [];
    for (int i = 0; i < items.length; i += columns) {
      rows.add(items.sublist(i, (i + columns).clamp(0, items.length)));
    }

    return Column(
      children: [
        for (int r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              children: [
                for (int c = 0; c < rows[r].length; c++) ...[
                  if (c > 0) _buildVerticalDivider(theme),
                  Expanded(child: _buildStatItem(theme, rows[r][c])),
                ],
                // 占位：不满一行时填充空列
                for (int c = rows[r].length; c < columns; c++) ...[
                  _buildVerticalDivider(theme),
                  const Expanded(child: SizedBox()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildScrollLayout(BuildContext context, List<_StatItemData> items) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) _buildVerticalDivider(theme),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildStatItem(theme, items[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(ThemeData theme, _StatItemData item) {
    return Tooltip(
      message: item.isTimeValue ? item.value : '${item.rawValue}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.isTimeValue
                ? item.value
                : NumberUtils.formatCount(item.rawValue),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider(ThemeData theme) {
    return Container(
      height: 20,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }

  String _formatValue(ProfileStatType stat, int value) {
    if (stat == ProfileStatType.timeRead ||
        stat == ProfileStatType.recentTimeRead) {
      return NumberUtils.formatDuration(value);
    }
    return NumberUtils.formatCount(value);
  }
}

/// 内部：从 providers 获取数据的卡片内容
class _StatsCardContent extends ConsumerWidget {
  final ProfileStatsConfig config;
  final VoidCallback? onEdit;

  const _StatsCardContent({
    required this.config,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = _resolveValues(ref);

    return ProfileStatsCardPreview(
      config: config,
      values: values,
      onTap: onEdit,
    );
  }

  /// 按需从不同数据源获取数据
  /// Riverpod FutureProvider 是惰性的，只有被 watch 才会发起请求
  Map<ProfileStatType, int> _resolveValues(WidgetRef ref) {
    switch (config.dataSource) {
      case StatsDataSource.summary:
        return _fromSummary(ref.watch(userSummaryProvider).value);
      case StatsDataSource.daily:
      case StatsDataSource.weekly:
      case StatsDataSource.monthly:
      case StatsDataSource.quarterly:
      case StatsDataSource.yearly:
        final period = getDirectoryPeriod(config.dataSource)!;
        final directoryItem = ref.watch(directoryItemProvider(period)).value;
        if (directoryItem != null) return _fromDirectory(directoryItem);
        return _fromSummary(ref.watch(userSummaryProvider).value);
      case StatsDataSource.connect:
        final connectStats = ref.watch(connectStatsProvider).value;
        if (connectStats != null) return _fromConnect(connectStats);
        return _fromSummary(ref.watch(userSummaryProvider).value);
    }
  }

  Map<ProfileStatType, int> _fromSummary(UserSummary? s) {
    if (s == null) return {};
    return {
      ProfileStatType.daysVisited: s.daysVisited,
      ProfileStatType.postsReadCount: s.postsReadCount,
      ProfileStatType.likesReceived: s.likesReceived,
      ProfileStatType.likesGiven: s.likesGiven,
      ProfileStatType.topicCount: s.topicCount,
      ProfileStatType.postCount: s.postCount,
      ProfileStatType.timeRead: s.timeRead,
      ProfileStatType.recentTimeRead: s.recentTimeRead,
      ProfileStatType.bookmarkCount: s.bookmarkCount,
      ProfileStatType.topicsEntered: s.topicsEntered,
    };
  }

  Map<ProfileStatType, int> _fromDirectory(DirectoryItem d) {
    return {
      ProfileStatType.daysVisited: d.daysVisited,
      ProfileStatType.postsReadCount: d.postsRead,
      ProfileStatType.likesReceived: d.likesReceived,
      ProfileStatType.likesGiven: d.likesGiven,
      ProfileStatType.topicCount: d.topicCount,
      ProfileStatType.postCount: d.postCount,
      ProfileStatType.topicsEntered: d.topicsEntered,
      if (d.timeRead != null) ProfileStatType.timeRead: d.timeRead!,
    };
  }

  Map<ProfileStatType, int> _fromConnect(ConnectStats c) {
    return {
      ProfileStatType.daysVisited: c.daysVisited,
      ProfileStatType.postsReadCount: c.postsRead,
      ProfileStatType.likesReceived: c.likesReceived,
      ProfileStatType.likesGiven: c.likesGiven,
      ProfileStatType.topicsEntered: c.topicsViewed,
      ProfileStatType.topicsRepliedTo: c.topicsRepliedTo,
      ProfileStatType.likesReceivedDays: c.likesReceivedDays,
      ProfileStatType.likesReceivedUsers: c.likesReceivedUsers,
    };
  }
}

class _StatItemData {
  final String value;
  final String label;
  final int rawValue;
  final bool isTimeValue;

  const _StatItemData({
    required this.value,
    required this.label,
    required this.rawValue,
    this.isTimeValue = false,
  });
}

/// 获取统计项的显示标签
String getStatLabel(ProfileStatType stat) {
  switch (stat) {
    case ProfileStatType.daysVisited:
      return S.current.profileStats_daysVisited;
    case ProfileStatType.postsReadCount:
      return S.current.profileStats_postsRead;
    case ProfileStatType.likesReceived:
      return S.current.profileStats_likesReceived;
    case ProfileStatType.likesGiven:
      return S.current.profileStats_likesGiven;
    case ProfileStatType.topicCount:
      return S.current.profileStats_topicCount;
    case ProfileStatType.postCount:
      return S.current.profileStats_postCount;
    case ProfileStatType.timeRead:
      return S.current.profileStats_timeRead;
    case ProfileStatType.recentTimeRead:
      return S.current.profileStats_recentTimeRead;
    case ProfileStatType.bookmarkCount:
      return S.current.profileStats_bookmarkCount;
    case ProfileStatType.topicsEntered:
      return S.current.profileStats_topicsEntered;
    case ProfileStatType.topicsRepliedTo:
      return S.current.profileStats_topicsRepliedTo;
    case ProfileStatType.likesReceivedDays:
      return S.current.profileStats_likesReceivedDays;
    case ProfileStatType.likesReceivedUsers:
      return S.current.profileStats_likesReceivedUsers;
  }
}

/// 获取数据源的显示标签
String getDataSourceLabel(StatsDataSource source) {
  switch (source) {
    case StatsDataSource.summary:
      return S.current.profileStats_sourceSummary;
    case StatsDataSource.daily:
      return S.current.profileStats_sourceDaily;
    case StatsDataSource.weekly:
      return S.current.profileStats_sourceWeekly;
    case StatsDataSource.monthly:
      return S.current.profileStats_sourceMonthly;
    case StatsDataSource.quarterly:
      return S.current.profileStats_sourceQuarterly;
    case StatsDataSource.yearly:
      return S.current.profileStats_sourceYearly;
    case StatsDataSource.connect:
      return S.current.profileStats_sourceConnect;
  }
}
