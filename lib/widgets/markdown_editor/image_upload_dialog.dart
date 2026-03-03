import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/toast_service.dart';
import 'image_compression_strategy.dart';
import 'image_editor_i18n_zh.dart';

/// 图片上传确认弹框结果
class ImageUploadResult {
  /// 处理后的图片路径
  final String path;

  /// 原始文件名
  final String originalName;

  ImageUploadResult({required this.path, required this.originalName});
}

/// 图片上传确认弹框
class ImageUploadDialog extends StatefulWidget {
  final String imagePath;
  final String? imageName;

  const ImageUploadDialog({
    super.key,
    required this.imagePath,
    this.imageName,
  });

  @override
  State<ImageUploadDialog> createState() => _ImageUploadDialogState();
}

class _ImageUploadDialogState extends State<ImageUploadDialog> {
  static const _qualityPreferenceKey = 'markdown_editor.image_upload_quality';

  late String _currentImagePath;
  late ImageCompressionStrategy _compressionStrategy;
  int _quality = 85;
  int? _originalSize;
  int? _estimatedSize;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _currentImagePath = widget.imagePath;
    _compressionStrategy = ImageCompressionStrategyFactory.fromPath(widget.imagePath);
    _restoreQualityPreference();
  }

  Future<void> _restoreQualityPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedQuality = prefs.getInt(_qualityPreferenceKey);
    if (!mounted) return;
    if (savedQuality != null) {
      setState(() {
        _quality = savedQuality.clamp(10, 100).toInt();
      });
    }
    await _loadImageInfo();
  }

  Future<void> _saveQualityPreference(int quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_qualityPreferenceKey, quality);
  }

  Future<void> _loadImageInfo() async {
    final file = File(_currentImagePath);
    if (await file.exists()) {
      final size = await file.length();
      final estimatedSize = _compressionStrategy.estimateCompressedSize(size, _quality);
      if (!mounted) return;
      setState(() {
        _originalSize = size;
        _estimatedSize = estimatedSize;
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _editImage() async {
    if (!_compressionStrategy.canEdit) {
      ToastService.showError('${_compressionStrategy.displayName} 暂不支持编辑，否则会丢失动画');
      return;
    }

    final result = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (context) => ProImageEditor.file(
          File(_currentImagePath),
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List bytes) async {
              Navigator.of(context).pop(bytes);
            },
          ),
          configs: ProImageEditorConfigs(
            i18n: kImageEditorI18nZh,
            imageGeneration: ImageGenerationConfigs(
              outputFormat: _editorOutputFormat,
              maxOutputSize: Size(1920, 1920),
            ),
          ),
        ),
      ),
    );

    if (result != null && mounted) {
      // 保存编辑后的图片到临时文件
      final tempDir = await getTemporaryDirectory();
      final editedPath = p.join(
        tempDir.path,
        'edited_${DateTime.now().millisecondsSinceEpoch}.${_editorExtension}',
      );
      await File(editedPath).writeAsBytes(result);

      setState(() {
        _currentImagePath = editedPath;
        _compressionStrategy = ImageCompressionStrategyFactory.fromPath(editedPath);
      });
      await _loadImageInfo();
    }
  }

  OutputFormat get _editorOutputFormat {
    if (p.extension(_currentImagePath).toLowerCase() == '.png') {
      return OutputFormat.png;
    }
    return OutputFormat.jpg;
  }

  String get _editorExtension => _editorOutputFormat == OutputFormat.png ? 'png' : 'jpg';

  Future<String> _compressImage() async {
    return _compressionStrategy.compress(_currentImagePath, _quality);
  }

  Future<void> _submit() async {
    setState(() => _isProcessing = true);

    try {
      await _saveQualityPreference(_quality);
      final compressedPath = await _compressImage();

      if (!mounted) return;

      Navigator.of(context).pop(ImageUploadResult(
        path: compressedPath,
        originalName: widget.imageName ?? p.basename(widget.imagePath),
      ));
    } catch (e) {
      if (!mounted) return;
      ToastService.showError('处理图片失败: $e');
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('上传图片确认'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 图片预览
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(_currentImagePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            if (!_compressionStrategy.supportsCompression)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${_compressionStrategy.displayName} 将保留原图上传，不执行客户端压缩。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),

            // 压缩质量滑块
            Row(
              children: [
                Text('压缩质量：', style: theme.textTheme.bodyMedium),
                Expanded(
                  child: Slider(
                    value: _quality.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    label: '$_quality%',
                    onChangeEnd: _isProcessing || !_compressionStrategy.supportsCompression
                        ? null
                        : (value) => _saveQualityPreference(value.round()),
                    onChanged: _isProcessing || !_compressionStrategy.supportsCompression
                        ? null
                        : (value) {
                          final nextQuality = value.round();
                          setState(() {
                            _quality = nextQuality;
                            if (_originalSize != null) {
                              _estimatedSize = _compressionStrategy.estimateCompressedSize(
                                _originalSize!,
                                nextQuality,
                              );
                            }
                          });
                        },
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$_quality%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            // 文件大小信息
            if (_originalSize != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.photo_size_select_large,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '原始大小：${_formatFileSize(_originalSize!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    if (_compressionStrategy.supportsCompression &&
                        _quality < 100 &&
                        _estimatedSize != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '约 ${_formatFileSize(_estimatedSize!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // 编辑图片按钮
            OutlinedButton.icon(
              onPressed: _isProcessing || !_compressionStrategy.canEdit ? null : _editImage,
              icon: const Icon(Icons.edit),
              label: Text(_compressionStrategy.canEdit ? '编辑图片' : '当前格式不支持编辑'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isProcessing ? null : _submit,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('上传'),
        ),
      ],
    );
  }
}

/// 显示图片上传确认弹框
Future<ImageUploadResult?> showImageUploadDialog(
  BuildContext context, {
  required String imagePath,
  String? imageName,
}) {
  return showDialog<ImageUploadResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ImageUploadDialog(
      imagePath: imagePath,
      imageName: imageName,
    ),
  );
}
