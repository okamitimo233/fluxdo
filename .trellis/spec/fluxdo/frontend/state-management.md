# State Management

> Riverpod 状态管理规范。

---

## Overview

本项目使用 Riverpod 进行状态管理，所有状态通过 Provider 管理，无全局变量。

**核心原则**：
- Provider 是唯一的状态管理方案
- 全局状态通过 Provider 共享
- 局部状态使用 StatefulWidget 或 StateNotifier
- 服务端状态使用 AsyncNotifier + 缓存

---

## State Categories

### 1. 全局状态（Global State）

**定义**：跨多个页面/组件共享的状态

**示例**：
- 当前用户信息
- 主题配置
- 语言设置
- 分类列表

**实现**：

```dart
// lib/providers/core_providers.dart
final currentUserProvider = AsyncNotifierProvider<CurrentUserNotifier, User?>(
  CurrentUserNotifier.new,
);

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
  (ref) => ThemeNotifier(),
);

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>(
  (ref) => LocaleNotifier(),
);

final categoryMapProvider = FutureProvider<Map<int, Category>?>((ref) async {
  final service = ref.watch(discourseServiceProvider);
  return service.getCategoryMap();
});
```

---

### 2. 局部状态（Local State）

**定义**：仅在单个页面/组件内使用的状态

**示例**：
- 文本输入框内容
- 当前选中的标签页
- 下拉菜单展开状态

**实现**：

```dart
// 使用 StatefulWidget
class SearchPage extends StatefulWidget {
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchController = TextEditingController();
  String _query = '';  // 局部状态

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
    );
  }
}

// 或使用 StateNotifierProvider
final searchQueryProvider = StateProvider<String>((ref) => '');
```

---

### 3. 服务端状态（Server State）

**定义**：从服务器获取的数据，需要缓存、刷新、错误处理

**示例**：
- 话题列表
- 用户资料
- 帖子详情

**实现**：

```dart
// lib/providers/topic_detail_provider.dart
class TopicDetailNotifier extends FamilyAsyncNotifier<TopicDetail?, int> {
  @override
  Future<TopicDetail?> build(int topicId) async {
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

  Future<void> loadMorePosts() async {
    final current = state.value;
    if (current == null) return;

    state = await AsyncValue.guard(() async {
      final service = ref.read(discourseServiceProvider);
      final morePosts = await service.getPosts(arg, current.postsCount);
      return current.copyWith(
        postStream: PostStream(
          posts: [...current.postStream.posts, ...morePosts],
          stream: current.postStream.stream,
        ),
      );
    });
  }
}
```

---

### 4. 派生状态（Derived State）

**定义**：从其他状态计算得出的状态

**示例**：
- 过滤后的话题列表
- 格式化的时间字符串
- 用户权限检查

**实现**：

```dart
// 从其他 Provider 计算派生状态
final filteredTopicsProvider = Provider<List<Topic>>((ref) {
  final allTopics = ref.watch(topicListProvider).value ?? [];
  final filter = ref.watch(topicFilterProvider);

  return allTopics.where((topic) {
    if (filter.categoryId != null && topic.categoryId != filter.categoryId.toString()) {
      return false;
    }
    if (filter.tags.isNotEmpty) {
      return filter.tags.any((tag) => topic.tags.any((t) => t.name == tag));
    }
    return true;
  }).toList();
});

// 使用 select 派生
final unreadCount = ref.watch(currentUserProvider.select((user) => user?.unreadNotifications ?? 0));
```

---

## When to Use Global State

### 提升为全局状态的判断标准

**应使用全局状态**：
- ✅ 多个页面需要访问
- ✅ 用户登录状态
- ✅ 应用配置（主题、语言）
- ✅ 缓存的服务端数据

**应使用局部状态**：
- ✅ 仅单个页面使用
- ✅ 临时 UI 状态（输入框内容、展开/折叠）
- ✅ 一次性的表单数据

**示例**：

```dart
// ✅ 全局状态：当前用户
final currentUserProvider = AsyncNotifierProvider<CurrentUserNotifier, User?>(
  CurrentUserNotifier.new,
);

// ✅ 局部状态：搜索框文本
class SearchPage extends StatefulWidget {
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';  // 仅此页面使用

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: (value) => setState(() => _query = value),
    );
  }
}
```

---

## Server State

### 缓存策略

**时间缓存**：

```dart
class CurrentUserNotifier extends AsyncNotifier<User?> {
  DateTime? _lastRefreshTime;
  static const _refreshCooldown = Duration(minutes: 2);

  Future<void> refreshSilently({bool force = false}) async {
    if (!force && _lastRefreshTime != null &&
        DateTime.now().difference(_lastRefreshTime!) < _refreshCooldown) {
      return;  // 冷却时间内跳过
    }

    final user = await _loadUser();
    _lastRefreshTime = DateTime.now();
    state = AsyncValue.data(user);
  }
}
```

**持久化缓存**：

```dart
class CurrentUserNotifier extends AsyncNotifier<User?> {
  static const String _cacheKey = 'current_user_cache';

  @override
  FutureOr<User?> build() async {
    // 1. 尝试从缓存加载
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      return User.fromCacheJson(jsonDecode(cached));
    }

    // 2. 从网络加载
    return await _loadFromNetwork();
  }

  Future<User?> _loadFromNetwork() async {
    final user = await service.getCurrentUser();
    if (user != null) {
      // 保存到缓存
      final prefs = await SharedPreferences.getInstance();
      prefs.setString(_cacheKey, jsonEncode(user.toCacheJson()));
    }
    return user;
  }
}
```

---

### 刷新策略

**手动刷新**：

```dart
Future<void> refresh() async {
  state = const AsyncValue.loading();
  state = await AsyncValue.guard(() => _loadData());
}
```

**后台静默刷新**：

```dart
void _refreshInBackground(User cachedUser) {
  Future(() async {
    try {
      final user = await _loadFromNetwork();
      if (user != null) {
        state = AsyncValue.data(user);  // 静默更新
      }
    } catch (_) {
      // 失败时保留缓存，不打断 UI
    }
  });
}
```

**下拉刷新**：

```dart
RefreshIndicator(
  onRefresh: () async {
    await ref.read(topicListProvider.notifier).refresh();
  },
  child: ListView(...),
)
```

---

## Common Mistakes

### ❌ 使用全局变量存储状态

```dart
// bad: 全局变量
User? globalUser;

void updateUser(User user) {
  globalUser = user;
}
```

### ✅ 正确：使用 Provider

```dart
final currentUserProvider = AsyncNotifierProvider<CurrentUserNotifier, User?>(
  CurrentUserNotifier.new,
);
```

---

### ❌ 在 Widget 中直接修改 Provider 状态

```dart
// bad: 直接修改状态
ref.read(currentUserProvider.notifier).state = User(name: 'Alice');
```

### ✅ 正确：通过 Notifier 方法修改

```dart
// good: 通过 Notifier 方法
ref.read(currentUserProvider.notifier).updateUser(User(name: 'Alice'));
```

---

### ❌ 不处理加载和错误状态

```dart
// bad: 只处理成功状态
final user = ref.watch(currentUserProvider);
if (user.value != null) {
  return Text(user.value!.name);
}
return Text('Guest');
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

### ❌ 过度使用全局状态

```dart
// bad: 所有状态都放在全局
final textControllerProvider = StateProvider<TextEditingController>((ref) {
  return TextEditingController();  // 文本控制器不需要全局
});
```

### ✅ 正确：局部状态使用 StatefulWidget

```dart
class MyForm extends StatefulWidget {
  @override
  State<MyForm> createState() => _MyFormState();
}

class _MyFormState extends State<MyForm> {
  final _controller = TextEditingController();  // 局部状态

  @override
  Widget build(BuildContext context) {
    return TextField(controller: _controller);
  }
}
```

---

## Examples

### 良好的状态管理示例

**`lib/providers/core_providers.dart`**：
- 全局状态：当前用户、主题、语言
- 缓存策略：SharedPreferences + 内存缓存
- 刷新策略：后台静默刷新 + 冷却时间

**`lib/providers/topic_detail_provider.dart`**：
- 服务端状态：话题详情
- 依赖注入：DiscourseService
- 提供方法：refresh(), loadMorePosts()

**`lib/pages/search_page.dart`**：
- 局部状态：搜索框文本
- StatefulWidget 管理临时状态
- 不提升为全局状态
