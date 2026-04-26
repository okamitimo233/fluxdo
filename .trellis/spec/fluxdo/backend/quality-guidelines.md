# Quality Guidelines

> 代码质量标准和最佳实践。

---

## Overview

本项目遵循 Dart/Flutter 最佳实践，强调代码可读性、可维护性和类型安全。

**核心原则**：
- 类型安全：充分利用 Dart 强类型系统
- 不可变数据：使用 `final` 和 `const`
- 清晰命名：变量、函数、类命名应自解释
- 单一职责：每个类/函数只做一件事

---

## Code Style

### 命名规范

**类名**：大驼峰（PascalCase）

```dart
class TopicService { }
class UserSummary { }
```

**变量/方法名**：小驼峰（camelCase）

```dart
final topicList = [];
void loadTopics() { }
```

**常量**：小驼峰，私有常量加下划线前缀

```dart
const Duration cacheDuration = Duration(minutes: 5);
const String _tokenKey = 'linux_do_token';
```

**私有成员**：下划线前缀

```dart
class DiscourseService {
  final Dio _dio;  // 私有字段
  String? _tToken;  // 私有字段
  
  void _handleError() { }  // 私有方法
}
```

---

### 类型声明

**显式声明类型**（不使用 `var`）：

```dart
// ✅ Good
final String username = 'alice';
final int count = 10;
final List<Topic> topics = [];
final Map<String, dynamic> json = {};

// ❌ Bad
final username = 'alice';
final count = 10;
var topics = [];
```

**例外**：类型明显时可省略

```dart
// Good: 类型明显
final topic = Topic.fromJson(json);
final user = await fetchUser();
```

**避免 `dynamic`**：

```dart
// ❌ Bad
final data = json['data'] as dynamic;

// ✅ Good
final data = json['data'] as Map<String, dynamic>;
final items = json['items'] as List<dynamic>;
```

---

### 不可变性

**使用 `final` 声明不可变变量**：

```dart
// ✅ Good
class User {
  final String username;
  final int age;

  const User({required this.username, required this.age});
}

// ❌ Bad
class User {
  String username;  // 可变字段
  int age;
}
```

**使用 `const` 构造函数**：

```dart
class Tag {
  final String name;
  
  const Tag({required this.name});  // const 构造函数
}

// 使用时
const tag = Tag(name: 'flutter');  // 编译时常量
```

---

### 空安全

**避免使用 `!` 操作符**（除非确定非空）：

```dart
// ❌ Bad: 强制解包可能崩溃
final user = currentUser!;

// ✅ Good: 安全处理空值
final user = currentUser;
if (user != null) {
  print(user.username);
}
```

**使用 `?` 和 `??` 操作符**：

```dart
// 安全调用
final name = user?.name ?? 'Unknown';

// 提供默认值
final count = json['count'] as int? ?? 0;
```

**模型类的空值处理**：

```dart
// lib/models/topic.dart
class Topic {
  final int id;
  final String title;
  final String? excerpt;  // 可空字段
  final DateTime? createdAt;  // 可空字段

  Topic({
    required this.id,
    required this.title,
    this.excerpt,  // 可选参数
    this.createdAt,
  });

  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',  // 提供默认值
      excerpt: json['excerpt'] as String?,  // 允许为空
      createdAt: TimeUtils.parseUtcTime(json['created_at'] as String?),
    );
  }
}
```

---

## Code Organization

### 文件结构

**标准文件结构**：

```dart
// 1. 导入（分组，空行分隔）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/topic.dart';
import '../services/discourse_service.dart';
import '../utils/time_utils.dart';

// 2. 常量
const Duration _cacheDuration = Duration(minutes: 5);

// 3. 主类
class TopicService {
  // 3.1 字段
  final Dio _dio;
  final Map<int, Topic> _cache = {};

  // 3.2 构造函数
  TopicService(this._dio);

  // 3.3 公开方法
  Future<Topic> getTopic(int id) async { }

  // 3.4 私有方法
  Topic _parseTopic(Map<String, dynamic> json) { }
}

// 4. 辅助类/枚举
enum TopicStatus { open, closed, archived }
```

---

### 函数设计

**单一职责**：

```dart
// ❌ Bad: 一个函数做太多事
Future<void> loadAndDisplayTopic(int id) async {
  final response = await dio.get('/t/$id.json');
  final topic = Topic.fromJson(response.data);
  setState(() {
    _topic = topic;
  });
  await analytics.logEvent('view_topic', params: {'id': id});
}

// ✅ Good: 分离职责
Future<Topic> _loadTopic(int id) async {
  final response = await dio.get('/t/$id.json');
  return Topic.fromJson(response.data);
}

void _updateUI(Topic topic) {
  setState(() {
    _topic = topic;
  });
}

Future<void> _logAnalytics(int id) async {
  await analytics.logEvent('view_topic', params: {'id': id});
}

// 调用
final topic = await _loadTopic(id);
_updateUI(topic);
await _logAnalytics(id);
```

**函数命名清晰**：

```dart
// ❌ Bad
void handle() { }

// ✅ Good
void handleTopicTap(Topic topic) { }
```

---

## Error Handling

### 不捕获所有异常

```dart
// ❌ Bad: 捕获所有异常但未处理
try {
  await fetchData();
} catch (e) {
  // 什么都不做
}

// ✅ Good: 记录日志并重新抛出
try {
  await fetchData();
} catch (e, st) {
  AppLogger.error('加载数据失败', error: e, stackTrace: st);
  rethrow;
}
```

### 使用特定异常类型

```dart
// ❌ Bad
if (response.statusCode != 200) {
  throw Exception('请求失败');
}

// ✅ Good
if (response.statusCode == 429) {
  throw RateLimitException(retryAfter);
}
if (response.statusCode! >= 500) {
  throw ServerException(response.statusCode!);
}
```

---

## Performance

### 避免重复构建

```dart
// ❌ Bad: 每次调用都创建新实例
Widget build(BuildContext context) {
  return Column(
    children: [
      _buildHeader(),  // 每次调用创建新 widget
      _buildBody(),
    ],
  );
}

Widget _buildHeader() {
  return Container(...);  // 每次都创建新实例
}

// ✅ Good: 使用 const 构造函数
Widget build(BuildContext context) {
  return Column(
    children: const [
      _Header(),  // const widget
      _Body(),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header();
  
  @override
  Widget build(BuildContext context) {
    return Container(...);
  }
}
```

---

### 避免不必要的 rebuild

```dart
// ❌ Bad: 整个列表 rebuild
final topics = ref.watch(topicListProvider);
return ListView.builder(
  itemCount: topics.length,
  itemBuilder: (context, index) {
    return TopicCard(topic: topics[index]);
  },
);

// ✅ Good: 使用 select 只监听需要的字段
final topicCount = ref.watch(topicListProvider.select((list) => list.length));
return Text('话题数: $topicCount');
```

---

## Testing

### 可测试性设计

```dart
// ❌ Bad: 硬编码依赖
class TopicService {
  final _dio = Dio();  // 无法替换为 mock
  
  Future<Topic> getTopic(int id) async {
    final response = await _dio.get('/t/$id.json');
    return Topic.fromJson(response.data);
  }
}

// ✅ Good: 依赖注入
class TopicService {
  final Dio _dio;
  
  TopicService(this._dio);  // 注入依赖
  
  Future<Topic> getTopic(int id) async {
    final response = await _dio.get('/t/$id.json');
    return Topic.fromJson(response.data);
  }
}

// 测试
test('should return topic', () async {
  final mockDio = MockDio();
  final service = TopicService(mockDio);
  
  when(mockDio.get('/t/1.json')).thenAnswer((_) async => Response(data: {'id': 1}));
  
  final topic = await service.getTopic(1);
  expect(topic.id, equals(1));
});
```

---

## Common Mistakes

### ❌ 使用 `var` 声明类型

```dart
var count = 10;
var user = User();
```

### ✅ 明确类型声明

```dart
final int count = 10;
final User user = User();
```

---

### ❌ 可变模型字段

```dart
class User {
  String username;
  int age;
  
  User({required this.username, required this.age});
}
```

### ✅ 不可变模型

```dart
class User {
  final String username;
  final int age;
  
  const User({required this.username, required this.age});
  
  User copyWith({String? username, int? age}) {
    return User(
      username: username ?? this.username,
      age: age ?? this.age,
    );
  }
}
```

---

### ❌ 大量嵌套 if-else

```dart
if (user != null) {
  if (user.isLoggedIn) {
    if (user.hasPermission) {
      // ...
    } else {
      // ...
    }
  } else {
    // ...
  }
}
```

### ✅ 早返回模式

```dart
if (user == null) return;
if (!user.isLoggedIn) return;
if (!user.hasPermission) return;

// 正常逻辑
```

---

### ❌ 硬编码字符串

```dart
throw Exception('Rate limit exceeded');
showDialog(child: Text('Error'));
```

### ✅ 使用国际化

```dart
throw RateLimitException(S.current.error_rateLimitedRetryLater);
showDialog(child: Text(S.current.error_title));
```

---

## Code Review Checklist

- [ ] 所有变量都有明确类型声明
- [ ] 模型类使用不可变字段 + `copyWith`
- [ ] 错误日志包含异常对象和堆栈信息
- [ ] 空值处理使用 `?` 和 `??`，避免 `!`
- [ ] 函数单一职责，命名清晰
- [ ] 使用 `AppLogger` 而非 `print()`
- [ ] 敏感数据使用 `SecureStorage`
- [ ] Provider 使用 `select` 避免不必要的 rebuild
