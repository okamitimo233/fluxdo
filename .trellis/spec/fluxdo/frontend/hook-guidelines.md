# Hook Guidelines

> Riverpod Provider 使用规范（Flutter 不使用 React Hooks）。

---

## Overview

本项目使用 Riverpod 进行状态管理，Provider 是核心概念。Flutter Hooks 不使用，所有状态管理通过 Riverpod 实现。

**核心原则**：
- 使用 `AsyncNotifier` 管理异步状态
- 使用 `Provider` 提供服务实例
- 使用 `select` 优化性能，避免不必要的 rebuild
- Provider 之间可以相互依赖

---

## Provider Types

### Provider - 服务提供者

**用途**：提供服务实例、工具类、配置

```dart
// 提供服务实例
final discourseServiceProvider = Provider((ref) => DiscourseService());

// 提供计算值
final categoryMapProvider = FutureProvider<Map<int, Category>?>((ref) async {
  final service = ref.watch(discourseServiceProvider);
  return service.getCategoryMap();
});
```

---

### AsyncNotifierProvider - 异步状态管理

**用途**：管理需要异步加载的数据（用户信息、话题列表等）

```dart
// lib/providers/core_providers.dart
class CurrentUserNotifier extends AsyncNotifier<User?> {
  @override
  FutureOr<User?> build() async {
    final service = ref.read(discourseServiceProvider);
    return await service.getCurrentUser();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(discourseServiceProvider);
      return await service.getCurrentUser();
    });
  }
}

final currentUserProvider = AsyncNotifierProvider<CurrentUserNotifier, User?>(
  CurrentUserNotifier.new,
);
```

---

### StateNotifierProvider - 同步状态管理

**用途**：管理复杂的同步状态（表单、过滤器等）

```dart
// lib/providers/topic_list/filter_provider.dart
class TopicFilterNotifier extends StateNotifier<TopicFilter> {
  TopicFilterNotifier() : super(const TopicFilter());

  void setCategory(int? categoryId) {
    state = state.copyWith(categoryId: categoryId);
  }

  void setTags(List<String> tags) {
    state = state.copyWith(tags: tags);
  }

  void clear() {
    state = const TopicFilter();
  }
}

final topicFilterProvider = StateNotifierProvider<TopicFilterNotifier, TopicFilter>(
  (ref) => TopicFilterNotifier(),
);
```

---

### StreamProvider - 流数据

**用途**：监听事件流、WebSocket、Message Bus

```dart
// lib/providers/core_providers.dart
final authErrorProvider = StreamProvider<String>((ref) {
  final service = ref.watch(discourseServiceProvider);
  return service.authErrorStream;
});

final authStateProvider = StreamProvider<void>((ref) {
  final service = ref.watch(discourseServiceProvider);
  return service.authStateStream;
});
```

---

## Data Fetching Patterns

### 1. 异步加载 + 缓存

```dart
// lib/providers/core_providers.dart
class CurrentUserNotifier extends AsyncNotifier<User?> {
  static const String _cacheKey = 'current_user_cache';

  @override
  FutureOr<User?> build() async {
    // 1. 尝试从缓存加载
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      final json = jsonDecode(cached) as Map<String, dynamic>;
      final user = User.fromCacheJson(json);

      // 2. 后台刷新
      _refreshInBackground(user);
      return user;
    }

    // 3. 从网络加载
    return await _loadFromNetwork();
  }

  Future<User?> _loadFromNetwork() async {
    final service = ref.read(discourseServiceProvider);
    final user = await service.getCurrentUser();

    if (user != null) {
      // 4. 保存到缓存
      final prefs = await SharedPreferences.getInstance();
      prefs.setString(_cacheKey, jsonEncode(user.toCacheJson()));
    }

    return user;
  }

  void _refreshInBackground(User cachedUser) {
    Future(() async {
      try {
        final user = await _loadFromNetwork();
        if (user != null) {
          state = AsyncValue.data(user);
        }
      } catch (_) {
        // 后台刷新失败，保留缓存
      }
    });
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadFromNetwork());
  }
}
```

---

### 2. 依赖其他 Provider

```dart
// lib/providers/user_summary_provider.dart
final userSummaryProvider = FutureProvider.family<UserSummary?, String>((ref, username) async {
  final service = ref.watch(discourseServiceProvider);
  return service.getUserSummary(username);
});

// 使用时传入参数
final summary = ref.watch(userSummaryProvider('alice'));
```

---

### 3. 条件加载

```dart
// lib/providers/topic_detail_provider.dart
final topicDetailProvider = AsyncNotifierProvider.family<TopicDetailNotifier, TopicDetail?, int>(
  TopicDetailNotifier.new,
);

class TopicDetailNotifier extends FamilyAsyncNotifier<TopicDetail?, int> {
  @override
  Future<TopicDetail?> build(int topicId) async {
    // 只有 topicId 有效时才加载
    if (topicId <= 0) return null;

    final service = ref.read(discourseServiceProvider);
    return await service.getTopic(topicId);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(discourseServiceProvider);
      return await service.getTopic(arg);
    });
  }
}
```

---

## Performance Optimization

### 使用 select 避免 rebuild

```dart
// ❌ Bad: 整个用户对象变化都会 rebuild
final user = ref.watch(currentUserProvider);
return Text(user?.name ?? 'Guest');

// ✅ Good: 只有 name 变化才 rebuild
final name = ref.watch(currentUserProvider.select((user) => user?.name));
return Text(name ?? 'Guest');
```

---

### 组合 Provider

```dart
// lib/providers/topic_list/topic_list_provider.dart
final topicListProvider = FutureProvider<List<Topic>>((ref) async {
  // 依赖其他 Provider
  final service = ref.watch(discourseServiceProvider);
  final filter = ref.watch(topicFilterProvider);

  return service.getTopics(
    categoryId: filter.categoryId,
    tags: filter.tags,
  );
});

// 过滤器变化时自动重新加载
final topicFilterProvider = StateNotifierProvider<TopicFilterNotifier, TopicFilter>(
  (ref) => TopicFilterNotifier(),
);
```

---

## Common Mistakes

### ❌ 在 Provider 中直接调用 setState

```dart
// bad: Provider 不应直接操作 UI
class MyNotifier extends AsyncNotifier<User> {
  Future<void> loadUser() async {
    final user = await fetchUser();
    setState(() {  // Provider 中没有 setState
      _user = user;
    });
  }
}
```

### ✅ 正确：使用 state 更新

```dart
class MyNotifier extends AsyncNotifier<User> {
  Future<void> loadUser() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => fetchUser());
  }
}
```

---

### ❌ 在 Widget 中创建 Provider

```dart
// bad: 每次 rebuild 都创建新 Provider
Widget build(BuildContext context) {
  final provider = Provider((ref) => MyService());
  return Consumer(builder: (context, ref, child) {
    final data = ref.watch(provider);
    return Text(data);
  });
}
```

### ✅ 正确：在顶层定义 Provider

```dart
// lib/providers/my_provider.dart
final myProvider = Provider((ref) => MyService());

// Widget 中使用
Widget build(BuildContext context, WidgetRef ref) {
  final data = ref.watch(myProvider);
  return Text(data);
}
```

---

### ❌ 监听整个 Provider 而非特定字段

```dart
// bad: 整个列表变化都 rebuild
final topics = ref.watch(topicListProvider);
final count = topics.length;  // 只需要长度

return Text('话题数: $count');
```

### ✅ 正确：使用 select

```dart
// good: 只有长度变化才 rebuild
final count = ref.watch(topicListProvider.select((topics) => topics.length));
return Text('话题数: $count');
```

---

### ❌ 忘记处理加载和错误状态

```dart
// bad: 只处理成功状态
final user = ref.watch(currentUserProvider);
return Text(user.value?.name ?? '');
```

### ✅ 正确：使用 when 处理所有状态

```dart
final userAsync = ref.watch(currentUserProvider);

return userAsync.when(
  data: (user) => Text(user?.name ?? 'Guest'),
  loading: () => const CircularProgressIndicator(),
  error: (e, st) => ErrorView(error: e),
);
```

---

## Examples

### 良好的 Provider 示例

**`lib/providers/core_providers.dart`**：
- 异步加载 + 缓存
- 后台刷新策略
- 错误处理

**`lib/providers/topic_detail_provider.dart`**：
- 复杂状态管理
- 依赖其他 Provider
- 提供刷新方法

**`lib/providers/message_bus/topic_tracking_providers.dart`**：
- StreamProvider 监听事件流
- 多个 Provider 组合
- 状态同步
