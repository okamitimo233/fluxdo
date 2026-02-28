import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ldc_providers.dart';
import '../pages/webview_page.dart';
import '../services/network/exceptions/oauth_exception.dart';

class LdcBalanceCard extends ConsumerWidget {
  final bool compact;
  final VoidCallback? onDisable;
  final VoidCallback? onReauthorize;

  const LdcBalanceCard({
    super.key,
    this.compact = false,
    this.onDisable,
    this.onReauthorize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ldcUserInfo = ref.watch(ldcUserInfoProvider);

    // 有错误且无旧数据时显示错误卡片
    if (ldcUserInfo.hasError && !ldcUserInfo.hasValue) {
      return _buildErrorCard(context, ref, ldcUserInfo.error!);
    }

    final userInfo = ldcUserInfo.value;
    if (userInfo == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    if (compact) {
      return GestureDetector(
        onTap: () => WebViewPage.open(
          context,
          'https://credit.linux.do/home',
          title: 'LINUX DO Credits',
        ),
        child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha:0.2)),
        ),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LDC 余额',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    userInfo.availableBalance,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(alpha:0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.trending_up_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '+${userInfo.dailyIncome}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      );
    }

    return GestureDetector(
      onTap: () => WebViewPage.open(
        context,
        'https://credit.linux.do/home',
        title: 'LINUX DO Credits',
      ),
      child: Card(
        elevation: 8,
        shadowColor: theme.colorScheme.primary.withValues(alpha:0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.tertiary,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // 装饰背景
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                Icons.account_balance_wallet_rounded,
                size: 150,
                color: Colors.white.withValues(alpha:0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'LINUX DO Credits',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white.withValues(alpha:0.9),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (onDisable != null)
                        GestureDetector(
                          onTap: onDisable,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.power_settings_new_rounded,
                              color: Colors.white.withValues(alpha:0.7),
                              size: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    userInfo.availableBalance,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 36,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.trending_up,
                          color: Colors.greenAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '今日收入 ${userInfo.dailyIncome}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha:0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildErrorCard(BuildContext context, WidgetRef ref, Object error) {
    final theme = Theme.of(context);
    final isExpired = error is OAuthExpiredException;

    if (compact) {
      return Card(
        elevation: 0,
        color: isExpired
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isExpired
                ? theme.colorScheme.error.withValues(alpha: 0.3)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isExpired
                      ? theme.colorScheme.error.withValues(alpha: 0.1)
                      : theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isExpired ? Icons.lock_clock_rounded : Icons.error_outline_rounded,
                  size: 20,
                  color: isExpired
                      ? theme.colorScheme.error
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LDC 余额',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      isExpired ? '授权已过期' : '加载失败',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isExpired
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (isExpired && onReauthorize != null)
                TextButton(
                  onPressed: onReauthorize,
                  child: const Text('重新授权'),
                )
              else
                TextButton(
                  onPressed: () => ref.read(ldcUserInfoProvider.notifier).refresh(),
                  child: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }

    // full 模式错误卡片
    return Card(
      elevation: 8,
      shadowColor: isExpired
          ? theme.colorScheme.error.withValues(alpha: 0.3)
          : theme.colorScheme.primary.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isExpired
                ? [
                    theme.colorScheme.error.withValues(alpha: 0.8),
                    theme.colorScheme.error.withValues(alpha: 0.6),
                  ]
                : [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                isExpired ? Icons.lock_clock_rounded : Icons.error_outline_rounded,
                size: 150,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isExpired ? Icons.lock_clock_rounded : Icons.error_outline_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'LINUX DO Credits',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (onDisable != null)
                        GestureDetector(
                          onTap: onDisable,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.power_settings_new_rounded,
                              color: Colors.white.withValues(alpha: 0.7),
                              size: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isExpired ? '授权已过期' : '加载失败',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isExpired ? '请重新授权以查看余额' : '请检查网络后重试',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isExpired && onReauthorize != null)
                    FilledButton.icon(
                      onPressed: onReauthorize,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重新授权'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => ref.read(ldcUserInfoProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重试'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
