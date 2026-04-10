import 'package:flutter/material.dart';
import '../../pages/user_profile_page.dart';
import '../../utils/url_helper.dart';

/// 嵌套帖子左侧头像（可点击跳转用户主页）
class NestedPostAvatar extends StatelessWidget {
  final String avatarTemplate;
  final String username;
  static const double size = 24.0;

  const NestedPostAvatar({
    super.key,
    required this.avatarTemplate,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserProfilePage(username: username)),
      ),
      child: CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(
          UrlHelper.resolveUrlWithCdn(
            avatarTemplate.replaceAll('{size}', '48'),
          ),
        ),
        onBackgroundImageError: (_, _) {},
      ),
    );
  }
}
