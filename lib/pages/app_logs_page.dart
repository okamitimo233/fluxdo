import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/log/logger_utils.dart';
import '../services/toast_service.dart';

/// 日志筛选类型
enum _LogFilter { all, error, request }

/// 应用日志查看页面
class AppLogsPage extends StatefulWidget {
  const AppLogsPage({super.key});

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  _LogFilter _filter = _LogFilter.all;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  List<Map<String, dynamic>> get _filteredEntries {
    switch (_filter) {
      case _LogFilter.all:
        return _entries;
      case _LogFilter.error:
        return _entries.where((e) => e['level'] == 'error').toList();
      case _LogFilter.request:
        return _entries.where((e) => e['type'] == 'request').toList();
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final entries = await LoggerUtils.readLogEntries();
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  Future<void> _copyDeviceInfo() async {
    final text = await LoggerUtils.getDeviceInfoText();
    await Clipboard.setData(ClipboardData(text: text));
    ToastService.showSuccess('已复制到剪贴板');
  }

  Future<void> _copyAll() async {
    final content = await LoggerUtils.readLogContent();
    if (content.trim().isEmpty) {
      ToastService.showInfo('暂无日志');
      return;
    }
    await Clipboard.setData(ClipboardData(text: content));
    ToastService.showSuccess('已复制到剪贴板');
  }

  Future<void> _shareLog() async {
    final path = await LoggerUtils.getShareFilePath();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: '应用日志'),
    );
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除日志'),
        content: const Text('确定要清除所有日志吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LoggerUtils.clearLogs();
      await _loadLogs();
      ToastService.showSuccess('日志已清除');
    }
  }

  /// 根据 level 获取图标和颜色
  (IconData, Color) _getIconAndColor(Map<String, dynamic> entry) {
    final level = entry['level']?.toString() ?? 'error';
    final type = entry['type']?.toString() ?? 'general';

    if (type == 'request') {
      return (Icons.http, Colors.blue);
    }

    switch (level) {
      case 'error':
        return (Icons.error_outline, Colors.red);
      case 'warning':
        return (Icons.warning_amber_outlined, Colors.orange);
      case 'info':
        return (Icons.info_outline, Colors.grey);
      default:
        return (Icons.article_outlined, Colors.grey);
    }
  }

  /// 获取卡片标题
  String _getTitle(Map<String, dynamic> entry) {
    final type = entry['type']?.toString() ?? 'general';
    if (type == 'request') {
      final method = entry['method']?.toString() ?? '';
      final url = entry['url']?.toString() ?? '';
      // 只显示路径部分
      final uri = Uri.tryParse(url);
      final path = uri?.path ?? url;
      return '$method $path';
    }

    final tag = entry['tag']?.toString();
    final errorType = entry['errorType']?.toString();
    final message = entry['message']?.toString() ?? '未知';

    if (tag != null && errorType != null) {
      return '[$tag] $errorType';
    }
    if (errorType != null && entry['level'] == 'error') {
      return errorType;
    }
    if (tag != null) {
      return '[$tag] $message';
    }
    return message;
  }

  /// 获取卡片副标题
  String _getSubtitle(Map<String, dynamic> entry) {
    final type = entry['type']?.toString() ?? 'general';
    if (type == 'request') {
      final statusCode = entry['statusCode'];
      final duration = entry['duration'];
      final parts = <String>[];
      if (statusCode != null) parts.add('$statusCode');
      if (duration != null) parts.add('${duration}ms');
      return parts.join(' · ');
    }

    final level = entry['level']?.toString() ?? 'error';
    if (level == 'error') {
      return entry['error']?.toString() ?? '未知错误';
    }
    return entry['message']?.toString() ?? '';
  }

  void _showDetail(Map<String, dynamic> entry) {
    final type = entry['type']?.toString() ?? 'general';
    if (type == 'request') {
      _showRequestDetail(entry);
    } else {
      _showGeneralDetail(entry);
    }
  }

  void _showGeneralDetail(Map<String, dynamic> entry) {
    final level = entry['level']?.toString() ?? 'error';
    final message = entry['message']?.toString() ?? '';
    final error = entry['error']?.toString();
    final errorType = entry['errorType']?.toString();
    final rawTrace = entry['stackTrace']?.toString();
    final stackTrace = rawTrace != null && rawTrace.trim().isNotEmpty
        ? rawTrace
        : null;
    final timestamp = entry['timestamp']?.toString() ?? '';
    final tag = entry['tag']?.toString();
    final appVersion = entry['appVersion']?.toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                tag != null ? '[$tag]' : level.toUpperCase(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                final detail = StringBuffer()
                  ..writeln('时间: $timestamp')
                  ..writeln('级别: $level');
                if (appVersion != null) detail.writeln('版本: $appVersion');
                if (tag != null) detail.writeln('标签: $tag');
                detail.writeln('消息: $message');
                if (error != null && error != message) {
                  detail.writeln('错误: $error');
                }
                if (errorType != null) detail.writeln('类型: $errorType');
                if (stackTrace != null) {
                  detail
                    ..writeln()
                    ..writeln('堆栈:')
                    ..writeln(stackTrace);
                }
                Clipboard.setData(ClipboardData(text: detail.toString()));
                ToastService.showSuccess('已复制到剪贴板');
              },
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailField('时间', timestamp),
              if (appVersion != null) _buildDetailField('版本', appVersion),
              _buildDetailField('消息', message),
              if (error != null && error != message)
                _buildDetailField('错误', error),
              if (errorType != null) _buildDetailField('错误类型', errorType),
              if (stackTrace != null) ...[
                const SizedBox(height: 12),
                Text(
                  '堆栈跟踪',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    stackTrace,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showRequestDetail(Map<String, dynamic> entry) {
    final timestamp = entry['timestamp']?.toString() ?? '';
    final method = entry['method']?.toString() ?? '';
    final url = entry['url']?.toString() ?? '';
    final statusCode = entry['statusCode']?.toString() ?? '';
    final duration = entry['duration'];
    final level = entry['level']?.toString() ?? 'info';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$method 请求',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                final detail = StringBuffer()
                  ..writeln('时间: $timestamp')
                  ..writeln('方法: $method')
                  ..writeln('URL: $url')
                  ..writeln('状态码: $statusCode');
                if (duration != null) detail.writeln('耗时: ${duration}ms');
                detail.writeln('级别: $level');
                Clipboard.setData(ClipboardData(text: detail.toString()));
                ToastService.showSuccess('已复制到剪贴板');
              },
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailField('时间', timestamp),
              _buildDetailField('方法', method),
              _buildDetailField('URL', url),
              _buildDetailField('状态码', statusCode),
              if (duration != null)
                _buildDetailField('耗时', '${duration}ms'),
              _buildDetailField('级别', level == 'warning' ? '失败' : '成功'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';
    final time = DateTime.tryParse(timestamp);
    if (time == null) return timestamp;
    final local = time.toLocal();
    return '${local.month}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用日志'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'deviceInfo':
                  _copyDeviceInfo();
                case 'copy':
                  _copyAll();
                case 'share':
                  _shareLog();
                case 'clear':
                  _clearLogs();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'deviceInfo',
                child: ListTile(
                  leading: Icon(Icons.smartphone),
                  title: Text('复制设备信息'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy),
                  title: Text('复制全部'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.share),
                  title: Text('分享日志'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('清除日志'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无日志',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredEntries;

    return Column(
      children: [
        // 筛选栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildFilterChip('全部', _LogFilter.all),
              const SizedBox(width: 8),
              _buildFilterChip('错误', _LogFilter.error),
              const SizedBox(width: 8),
              _buildFilterChip('请求', _LogFilter.request),
            ],
          ),
        ),
        // 日志列表
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    '无匹配日志',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadLogs,
                  child: ListView.builder(
                    itemCount: filtered.length,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final (icon, color) = _getIconAndColor(entry);
                      final title = _getTitle(entry);
                      final subtitle = _getSubtitle(entry);
                      final timestamp =
                          _formatTimestamp(entry['timestamp']?.toString());

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Icon(icon, color: color),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              const SizedBox(height: 4),
                              Text(
                                timestamp,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                              ),
                            ],
                          ),
                          onTap: () => _showDetail(entry),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, _LogFilter filter) {
    final selected = _filter == filter;
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (value) {
        setState(() => _filter = filter);
      },
    );
  }
}
