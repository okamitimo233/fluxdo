import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ai_model_manager/ai_model_manager.dart';

import '../providers/preferences_provider.dart';
import '../providers/theme_provider.dart';
import '../services/data_management/cache_size_service.dart';
import '../services/data_management/data_backup_service.dart';
import '../services/discourse_cache_manager.dart';
import '../services/network/cookie/cookie_jar_service.dart';
import '../services/toast_service.dart';

/// 数据管理页面
class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  int _imageCacheSize = -1;
  int _aiChatDataSize = -1;
  int _cookieCacheSize = -1;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSizes();
  }

  Future<void> _loadCacheSizes() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final results = await Future.wait([
      CacheSizeService.getImageCacheSize(),
      CacheSizeService.getAiChatDataSize(prefs),
      CacheSizeService.getCookieCacheSize(),
    ]);
    if (mounted) {
      setState(() {
        _imageCacheSize = results[0];
        _aiChatDataSize = results[1];
        _cookieCacheSize = results[2];
      });
    }
  }

  int get _totalCacheSize {
    int total = 0;
    if (_imageCacheSize > 0) total += _imageCacheSize;
    if (_aiChatDataSize > 0) total += _aiChatDataSize;
    if (_cookieCacheSize > 0) total += _cookieCacheSize;
    return total;
  }

  String _formatCacheSize(int size) {
    if (size < 0) return '计算中...';
    if (size == 0) return '无缓存';
    return CacheSizeService.formatSize(size);
  }

  Future<void> _clearImageCache() async {
    setState(() => _isClearing = true);
    try {
      await Future.wait([
        DiscourseCacheManager().emptyCache(),
        EmojiCacheManager().emptyCache(),
        ExternalImageCacheManager().emptyCache(),
      ]);
      // emptyCache() 只清除了索引，磁盘文件可能残留，需要删除整个目录
      await CacheSizeService.deleteImageCacheDirs();
      PaintingBinding.instance.imageCache.clear();
      setState(() => _imageCacheSize = 0);
      ToastService.showSuccess('图片缓存已清除');
    } catch (e) {
      ToastService.showError('清除失败: $e');
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _clearAiChatData() async {
    final confirmed = await _showConfirmDialog(
      title: '清除 AI 聊天数据',
      content: '将删除所有 AI 聊天记录，此操作不可恢复。',
    );
    if (confirmed != true) return;

    setState(() => _isClearing = true);
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await AiChatStorageService(prefs).deleteAllSessions();
      setState(() => _aiChatDataSize = 0);
      ToastService.showSuccess('AI 聊天数据已清除');
    } catch (e) {
      ToastService.showError('清除失败: $e');
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _clearCookieCache() async {
    final confirmed = await _showConfirmDialog(
      title: '清除 Cookie 缓存',
      content: '清除 Cookie 后需要重新登录，确定要继续吗？',
      confirmText: '清除并退出登录',
      isDestructive: true,
    );
    if (confirmed != true) return;

    setState(() => _isClearing = true);
    try {
      await _doClearCookies();
      setState(() => _cookieCacheSize = 0);
      ToastService.showSuccess('Cookie 缓存已清除，请重新登录');
    } catch (e) {
      ToastService.showError('清除失败: $e');
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await _showConfirmDialog(
      title: '清除所有缓存',
      content: '将清除所有缓存数据，包括图片缓存、AI 聊天数据和 Cookie。\n\n'
          '清除 Cookie 后需要重新登录。',
      confirmText: '全部清除',
      isDestructive: true,
    );
    if (confirmed != true) return;

    setState(() => _isClearing = true);
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await Future.wait([
        DiscourseCacheManager().emptyCache(),
        EmojiCacheManager().emptyCache(),
        ExternalImageCacheManager().emptyCache(),
        AiChatStorageService(prefs).deleteAllSessions(),
        _doClearCookies(),
      ]);
      await CacheSizeService.deleteImageCacheDirs();
      PaintingBinding.instance.imageCache.clear();
      setState(() {
        _imageCacheSize = 0;
        _aiChatDataSize = 0;
        _cookieCacheSize = 0;
      });
      ToastService.showSuccess('所有缓存已清除，请重新登录');
    } catch (e) {
      ToastService.showError('清除失败: $e');
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  /// 清除 Cookie 文件和内存
  Future<void> _doClearCookies() async {
    // 清除 CookieJar 内存中的 cookie
    final cookieJar = CookieJarService().cookieJar;
    await cookieJar.deleteAll();
  }

  Future<void> _exportData() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final filePath = await DataBackupService.exportToFile(prefs);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath, mimeType: 'application/json')],
          subject: 'FluxDO 数据备份',
        ),
      );
    } catch (e) {
      ToastService.showError('导出失败: $e');
    }
  }

  Future<void> _importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final backup = await DataBackupService.parseBackupFile(filePath);
      final data = backup['data'] as Map<String, dynamic>;
      final apiKeys = backup['apiKeys'] as Map<String, dynamic>?;
      final appVersion = backup['appVersion'] as String? ?? '未知';
      final exportTime = backup['exportTime'] as String? ?? '未知';

      if (!mounted) return;

      final details = StringBuffer()
        ..writeln('备份来源: v$appVersion')
        ..writeln('导出时间: $exportTime')
        ..writeln('包含 ${data.length} 项设置');
      if (apiKeys != null && apiKeys.isNotEmpty) {
        details.writeln('包含 ${apiKeys.length} 个 API Key');
      }
      details.write('\n导入后将覆盖当前对应的设置项，需要重启应用生效。');

      final confirmed = await _showConfirmDialog(
        title: '确认导入',
        content: details.toString(),
        confirmText: '导入并重启',
      );
      if (confirmed != true) return;

      final prefs = ref.read(sharedPreferencesProvider);
      await DataBackupService.importData(prefs, backup);
      ToastService.showSuccess('数据已导入，请重启应用');
    } on FormatException catch (e) {
      ToastService.showError(e.message);
    } catch (e) {
      ToastService.showError('导入失败: $e');
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String content,
    String confirmText = '确定',
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferences = ref.watch(preferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Section 1 — 缓存管理
          _buildSectionHeader(theme, Icons.cleaning_services_rounded, '缓存管理'),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildCacheTile(
                  icon: Icons.image_rounded,
                  title: '图片缓存',
                  size: _imageCacheSize,
                  onClear: _isClearing ? null : _clearImageCache,
                ),
                _buildDivider(theme),
                _buildCacheTile(
                  icon: Icons.smart_toy_rounded,
                  title: 'AI 聊天数据',
                  size: _aiChatDataSize,
                  onClear: _isClearing ? null : _clearAiChatData,
                ),
                _buildDivider(theme),
                _buildCacheTile(
                  icon: Icons.cookie_rounded,
                  title: 'Cookie 缓存',
                  size: _cookieCacheSize,
                  onClear: _isClearing ? null : _clearCookieCache,
                ),
                _buildDivider(theme),
                ListTile(
                  leading: Icon(
                    Icons.delete_sweep_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: const Text('清除所有缓存'),
                  subtitle: Text(_formatCacheSize(_totalCacheSize)),
                  trailing: TextButton(
                    onPressed: _isClearing || _totalCacheSize <= 0
                        ? null
                        : _clearAllCache,
                    child: const Text('清除'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section 2 — 自动管理
          _buildSectionHeader(theme, Icons.auto_delete_rounded, '自动管理'),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              title: const Text('退出时清除图片缓存'),
              subtitle: const Text('下次启动时自动清除图片缓存'),
              secondary: Icon(
                Icons.auto_delete_rounded,
                color: preferences.clearCacheOnExit
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              value: preferences.clearCacheOnExit,
              onChanged: (value) {
                ref.read(preferencesProvider.notifier).setClearCacheOnExit(value);
              },
            ),
          ),
          const SizedBox(height: 24),

          // Section 3 — 数据备份
          _buildSectionHeader(theme, Icons.backup_rounded, '数据备份'),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_rounded),
                  title: const Text('导出数据'),
                  subtitle: const Text('将偏好设置导出为文件'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    size: 20,
                  ),
                  onTap: _exportData,
                ),
                _buildDivider(theme),
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('导入数据'),
                  subtitle: const Text('从备份文件恢复偏好设置'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    size: 20,
                  ),
                  onTap: _importData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCacheTile({
    required IconData icon,
    required String title,
    required int size,
    required VoidCallback? onClear,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(_formatCacheSize(size)),
      trailing: TextButton(
        onPressed: size <= 0 ? null : onClear,
        child: const Text('清除'),
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(
      height: 1,
      indent: 56,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
    );
  }
}
