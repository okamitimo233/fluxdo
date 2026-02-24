import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'discourse_cache_manager.dart';

/// AVIF 图片 Provider
///
/// 通过 DiscourseCacheManager 下载/缓存文件，
/// 使用 flutter_avif 的 decodeAvif 解码为 dart:ui Image
/// 支持单帧和多帧（动画）AVIF
class AvifImageProvider extends ImageProvider<AvifImageProvider> {
  final String url;
  final double scale;

  const AvifImageProvider(this.url, {this.scale = 1.0});

  @override
  Future<AvifImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<AvifImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    AvifImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return _AvifAnimatedImageStreamCompleter(
      framesLoader: _decodeAvif(key),
      scale: key.scale,
    );
  }

  Future<List<AvifFrameInfo>> _decodeAvif(AvifImageProvider key) async {
    final file = await DiscourseCacheManager().getSingleFile(key.url);
    final bytes = await file.readAsBytes();
    return decodeAvif(bytes);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AvifImageProvider &&
        other.url == url &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'AvifImageProvider("$url", scale: $scale)';
}

/// AVIF 多帧图片流 Completer
///
/// 单帧 AVIF 直接显示；多帧 AVIF 按帧 duration 循环播放。
/// 无监听时自动暂停动画，重新添加监听时恢复。
class _AvifAnimatedImageStreamCompleter extends ImageStreamCompleter {
  _AvifAnimatedImageStreamCompleter({
    required Future<List<AvifFrameInfo>> framesLoader,
    required this.scale,
  }) {
    framesLoader.then(_handleFrames, onError: (Object error, StackTrace stack) {
      reportError(
        context: ErrorDescription('解码 AVIF'),
        exception: error,
        stack: stack,
      );
    });
  }

  final double scale;
  List<AvifFrameInfo>? _frames;
  int _currentFrameIndex = 0;
  Timer? _timer;

  void _handleFrames(List<AvifFrameInfo> frames) {
    if (frames.isEmpty) {
      reportError(
        context: ErrorDescription('AVIF 解码失败：无帧数据'),
        exception: Exception('AVIF 解码失败：无帧数据'),
        stack: StackTrace.current,
      );
      return;
    }
    _frames = frames;
    _emitFrame();
  }

  void _emitFrame() {
    final frames = _frames;
    if (frames == null || !hasListeners) return;

    final frame = frames[_currentFrameIndex];
    setImage(ImageInfo(image: frame.image.clone(), scale: scale));

    // 多帧时调度下一帧
    if (frames.length > 1) {
      final delay = frame.duration.inMilliseconds > 0
          ? frame.duration
          : const Duration(milliseconds: 100);
      _currentFrameIndex = (_currentFrameIndex + 1) % frames.length;
      _timer?.cancel();
      _timer = Timer(delay, _emitFrame);
    }
  }

  @override
  void addListener(ImageStreamListener listener) {
    final hadListeners = hasListeners;
    super.addListener(listener);
    // 恢复已暂停的动画
    if (!hadListeners && _frames != null && _frames!.length > 1 && _timer == null) {
      _emitFrame();
    }
  }

  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }
}
