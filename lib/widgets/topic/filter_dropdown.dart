import 'package:flutter/material.dart';
import '../../providers/topic_list_provider.dart';
import '../../providers/topic_sort_provider.dart';
import 'sort_and_tags_bar.dart';

/// 下拉样式
enum DropdownStyle {
  /// 带背景框完整版（用于排序栏）
  normal,

  /// 紧凑版图标 + 文字（用于折叠状态）
  compact,
}

/// 筛选下拉公共组件（原 SortDropdown）
class FilterDropdown extends StatelessWidget {
  final TopicListFilter currentFilter;
  final bool isLoggedIn;
  final ValueChanged<TopicListFilter> onFilterChanged;
  final DropdownStyle style;

  const FilterDropdown({
    super.key,
    required this.currentFilter,
    required this.isLoggedIn,
    required this.onFilterChanged,
    this.style = DropdownStyle.normal,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<TopicListFilter>(
      onSelected: onFilterChanged,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tooltip: '筛选: ${filterLabel(currentFilter)}',
      itemBuilder: (context) {
        return filterOptions
            .where((option) => isLoggedIn || (option.$1 != TopicListFilter.newTopics && option.$1 != TopicListFilter.unread && option.$1 != TopicListFilter.unseen))
            .map((option) => PopupMenuItem<TopicListFilter>(
                  value: option.$1,
                  child: Row(
                    children: [
                      if (option.$1 == currentFilter)
                        Icon(Icons.check, size: 16, color: colorScheme.primary)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(option.$2),
                    ],
                  ),
                ))
            .toList();
      },
      child: style == DropdownStyle.compact
          ? _buildCompactChild(colorScheme)
          : _buildNormalChild(colorScheme),
    );
  }

  Widget _buildNormalChild(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            filterLabel(currentFilter),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 18, color: colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildCompactChild(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_list, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 2),
          Text(
            filterLabel(currentFilter),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 排序下拉组件（真正的字段排序）
class OrderDropdown extends StatelessWidget {
  final TopicSortOrder currentOrder;
  final bool ascending;
  final ValueChanged<TopicSortOrder> onOrderChanged;
  final VoidCallback onToggleAscending;
  final DropdownStyle style;

  const OrderDropdown({
    super.key,
    required this.currentOrder,
    required this.ascending,
    required this.onOrderChanged,
    required this.onToggleAscending,
    this.style = DropdownStyle.normal,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = currentOrder != TopicSortOrder.defaultOrder;

    return PopupMenuButton<TopicSortOrder>(
      onSelected: (order) {
        if (order == currentOrder && order != TopicSortOrder.defaultOrder) {
          // 再次点击已选中的排序项时，切换升降序
          onToggleAscending();
        } else {
          onOrderChanged(order);
        }
      },
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tooltip: '排序: ${currentOrder.label}',
      itemBuilder: (context) {
        return TopicSortOrder.values.map((order) {
          final isSelected = order == currentOrder;
          return PopupMenuItem<TopicSortOrder>(
            value: order,
            child: Row(
              children: [
                if (isSelected)
                  Icon(Icons.check, size: 16, color: colorScheme.primary)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(order.label)),
                // 当前选中的非默认项显示方向箭头
                if (isSelected && order != TopicSortOrder.defaultOrder)
                  Icon(
                    ascending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: colorScheme.primary,
                  ),
              ],
            ),
          );
        }).toList();
      },
      child: style == DropdownStyle.compact
          ? _buildCompactChild(colorScheme, isActive)
          : _buildNormalChild(colorScheme, isActive),
    );
  }

  Widget _buildNormalChild(ColorScheme colorScheme, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currentOrder.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isActive ? colorScheme.primary : colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 2),
          if (isActive)
            Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: colorScheme.primary,
            )
          else
            Icon(Icons.arrow_drop_down, size: 18, color: colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildCompactChild(ColorScheme colorScheme, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sort,
            size: 18,
            color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          if (isActive) ...[
            const SizedBox(width: 2),
            Text(
              currentOrder.label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
            Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}
