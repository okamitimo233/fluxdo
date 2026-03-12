import '../constants.dart';

class UrlHelper {
  /// 修复相对路径 URL
  /// 支持协议相对路径（//example.com/...）和站内相对路径（/path/...）
  static String resolveUrl(String url) {
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    if (url.startsWith('http')) {
      return url;
    }
    if (url.startsWith('/')) {
      return '${AppConstants.baseUrl}$url';
    }
    // 相对路径（如 letter_avatar_proxy/v4/...）
    return '${AppConstants.baseUrl}/$url';
  }
}
