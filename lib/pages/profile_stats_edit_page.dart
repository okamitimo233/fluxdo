import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile_stats_config.dart';
import '../models/user.dart';
import '../models/directory_item.dart';
import '../models/connect_stats.dart';
import '../providers/core_providers.dart';
import '../providers/directory_providers.dart';
import '../providers/profile_stats_provider.dart';
import '../widgets/profile_stats_card.dart';
import '../l10n/s.dart';

/// 统计卡片编辑页
class ProfileStatsEditPage extends ConsumerWidget {
  const ProfileStatsEditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(profileStatsConfigProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.current.profileStats_editTitle),
        actions: [
          // 重置按钮
          TextButton(
            onPressed: () {
              ref.read(profileStatsConfigProvider.notifier).update(
                const ProfileStatsConfig(),
              );
            },
            child: Text(S.current.common_reset),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 实时预览
          _SectionHeader(title: S.current.common_preview),
          const SizedBox(height: 8),
          _PreviewSection(config: config),
          const SizedBox(height: 24),

          // 数据源
          _SectionHeader(title: S.current.profileStats_dataSource),
          const SizedBox(height: 8),
          _DataSourceSelector(config: config),
          const SizedBox(height: 24),

          // 布局设置
          _SectionHeader(title: S.current.profileStats_layoutSettings),
          const SizedBox(height: 8),
          _LayoutSettings(config: config),
          const SizedBox(height: 24),

          // 已添加项目
          _SectionHeader(
            title: S.current.profileStats_enabledItems,
            trailing: config.enabledStats.isNotEmpty
                ? Text(
                    '${config.enabledStats.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          _EnabledStatsSection(config: config),
          const SizedBox(height: 24),

          // 可添加项目
          _SectionHeader(title: S.current.profileStats_availableItems),
          const SizedBox(height: 8),
          _AvailableStatsSection(config: config),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

/// 区块标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 预览区域
class _PreviewSection extends ConsumerWidget {
  final ProfileStatsConfig config;
  const _PreviewSection({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = _resolvePreviewValues(ref, config);
    return ProfileStatsCardPreview(
      config: config,
      values: values,
    );
  }

  Map<ProfileStatType, int> _resolvePreviewValues(
    WidgetRef ref,
    ProfileStatsConfig config,
  ) {
    switch (config.dataSource) {
      case StatsDataSource.summary:
        return _fromSummary(ref.watch(userSummaryProvider).value);
      case StatsDataSource.daily:
      case StatsDataSource.weekly:
      case StatsDataSource.monthly:
      case StatsDataSource.quarterly:
      case StatsDataSource.yearly:
        final period = getDirectoryPeriod(config.dataSource)!;
        final d = ref.watch(directoryItemProvider(period)).value;
        if (d != null) return _fromDirectory(d);
        return _fromSummary(ref.watch(userSummaryProvider).value);
      case StatsDataSource.connect:
        final c = ref.watch(connectStatsProvider).value;
        if (c != null) return _fromConnect(c);
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

/// 数据源选择（横向 Chip 列表）
class _DataSourceSelector extends ConsumerWidget {
  final ProfileStatsConfig config;
  const _DataSourceSelector({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(profileStatsConfigProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final source in StatsDataSource.values) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(getDataSourceLabel(source)),
                selected: config.dataSource == source,
                onSelected: (_) => notifier.setDataSource(source),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 布局设置（紧凑的 Chip 行）
class _LayoutSettings extends ConsumerWidget {
  final ProfileStatsConfig config;
  const _LayoutSettings({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(profileStatsConfigProvider.notifier);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 布局模式
            _SettingRow(
              label: S.current.profileStats_layoutMode,
              child: SegmentedButton<StatsLayoutMode>(
                segments: [
                  ButtonSegment(
                    value: StatsLayoutMode.grid,
                    icon: const Icon(Icons.grid_view_rounded, size: 18),
                    label: Text(S.current.profileStats_layoutGrid),
                  ),
                  ButtonSegment(
                    value: StatsLayoutMode.scroll,
                    icon: const Icon(Icons.view_column_rounded, size: 18),
                    label: Text(S.current.profileStats_layoutScroll),
                  ),
                ],
                selected: {config.layoutMode},
                onSelectionChanged: (set) =>
                    notifier.setLayoutMode(set.first),
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: theme.textTheme.labelMedium,
                ),
              ),
            ),

            // 每行数量（仅网格模式）
            if (config.layoutMode == StatsLayoutMode.grid) ...[
              Divider(
                height: 24,
                thickness: 0.5,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              _SettingRow(
                label: S.current.profileStats_columnsPerRow,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 2, label: Text('2')),
                    ButtonSegment(value: 3, label: Text('3')),
                    ButtonSegment(value: 4, label: Text('4')),
                  ],
                  selected: {config.columnsPerRow},
                  onSelectionChanged: (set) =>
                      notifier.setColumnsPerRow(set.first),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: theme.textTheme.labelMedium,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 设置行（标签 + 控件）
class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _SettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 已添加项目（可拖拽排序）
class _EnabledStatsSection extends ConsumerWidget {
  final ProfileStatsConfig config;
  const _EnabledStatsSection({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(profileStatsConfigProvider.notifier);

    if (config.enabledStats.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.inbox_rounded,
                  size: 32,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  S.current.profileStats_noItemsSelected,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: config.enabledStats.length,
        onReorder: notifier.reorderStats,
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(8),
                child: child,
              );
            },
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final stat = config.enabledStats[index];
          return Material(
            key: ValueKey(stat),
            color: Colors.transparent,
            child: ListTile(
              leading: ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.4),
                ),
              ),
              title: Text(
                getStatLabel(stat),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: IconButton(
                icon: Icon(
                  Icons.remove_circle_outline_rounded,
                  color: theme.colorScheme.error.withValues(alpha: 0.6),
                  size: 22,
                ),
                onPressed: () => notifier.removeStat(stat),
              ),
              dense: true,
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }
}

/// 可添加项目
class _AvailableStatsSection extends ConsumerWidget {
  final ProfileStatsConfig config;
  const _AvailableStatsSection({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(profileStatsConfigProvider.notifier);

    final available = ProfileStatType.values
        .where((stat) => !config.enabledStats.contains(stat))
        .toList();

    if (available.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              S.current.profileStats_allItemsAdded,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < available.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            _AvailableStatTile(
              stat: available[i],
              config: config,
              notifier: notifier,
            ),
          ],
        ],
      ),
    );
  }
}

class _AvailableStatTile extends StatelessWidget {
  final ProfileStatType stat;
  final ProfileStatsConfig config;
  final ProfileStatsConfigNotifier notifier;
  const _AvailableStatTile({
    required this.stat,
    required this.config,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compatible = isStatCompatible(stat, config.dataSource);

    return ListTile(
      enabled: compatible,
      title: Text(
        getStatLabel(stat),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: compatible
              ? null
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      ),
      subtitle: compatible
          ? null
          : Text(
              S.current.profileStats_incompatibleSource,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
      trailing: IconButton(
        icon: Icon(
          Icons.add_circle_outline_rounded,
          color: compatible
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
          size: 22,
        ),
        onPressed: compatible ? () => notifier.addStat(stat) : null,
      ),
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }
}
