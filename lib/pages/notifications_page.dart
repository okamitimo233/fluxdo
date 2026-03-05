import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/discourse_providers.dart';
import '../utils/notification_navigation.dart';
import '../widgets/notification/notification_item.dart';
import '../widgets/notification/notification_list_skeleton.dart';
import '../widgets/common/error_view.dart';

/// 通知历史列表页面（独立分页，不受 messageBus 干扰）
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(notificationListProvider.notifier).loadMore();
    }
  }

  Future<void> _onRefresh() async {
    await ref.read(notificationListProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationListProvider);
    final systemAvatarTemplate = ref.watch(systemUserAvatarTemplateProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              await ref.read(notificationListProvider.notifier).markAllAsRead();
              // 快捷面板下次打开时会自动 silentRefresh 同步已读状态
            },
            tooltip: '全部标为已读',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: notificationsAsync.when(
          data: (notifications) {
            if (notifications.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('暂无通知', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.builder(
              controller: _scrollController,
              itemCount: notifications.length + 1,
              itemBuilder: (context, index) {
                if (index == notifications.length) {
                  final notifier = ref.read(notificationListProvider.notifier);
                  if (notifier.isLoadMoreFailed) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: GestureDetector(
                          onTap: () => notifier.retryLoadMore(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh, size: 16, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                '加载失败，点击重试',
                                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (!notifier.hasMore) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text('没有更多了', style: TextStyle(color: Colors.grey)),
                      ),
                    );
                  }
                  if (notificationsAsync.isLoading && !notificationsAsync.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return const SizedBox();
                }
                final notification = notifications[index];
                return NotificationItem(
                  notification: notification,
                  systemAvatarTemplate: systemAvatarTemplate,
                  onTap: () => handleNotificationTap(context, ref, notification),
                );
              },
            );
          },
          loading: () => const NotificationListSkeleton(),
          error: (error, stack) => ErrorView(
            error: error,
            stackTrace: stack,
            onRetry: _onRefresh,
          ),
        ),
      ),
    );
  }
}
