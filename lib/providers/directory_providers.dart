import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/directory_item.dart';
import '../models/connect_stats.dart';
import '../services/network/discourse_dio.dart';
import 'core_providers.dart';

/// Directory API Provider（按时间段查询）
final directoryItemProvider = FutureProvider.family<DirectoryItem?, String>(
  (ref, period) async {
    final service = ref.watch(discourseServiceProvider);
    final username = ref.watch(
      currentUserProvider.select((value) => value.value?.username),
    );
    if (username == null) return null;

    final json = await service.getDirectoryItem(username, period);
    if (json == null) return null;
    return DirectoryItem.fromJson(json);
  },
);

/// connect.linux.do 统计 Provider
final connectStatsProvider = FutureProvider<ConnectStats?>((ref) async {
  final user = ref.watch(
    currentUserProvider.select((value) => value.value),
  );
  if (user == null) return null;

  final dio = DiscourseDio.create();
  final response = await dio.get('https://connect.linux.do/');
  if (response.statusCode == 200) {
    return ConnectStats.fromHtml(response.data);
  }
  return null;
});
