# Type Safety

> Dart 类型安全规范。

---

## Overview

本项目使用 Dart 强类型系统，避免使用 `dynamic`，充分利用类型推断和空安全特性。

**核心原则**：
- 显式类型声明优于类型推断
- 避免使用 `dynamic` 和 `Object`
- 使用空安全特性（`?`, `??`, `?.`）
- 模型类实现完整的类型转换方法

---

## Type Organization

### 类型定义位置

**模型类**：`lib/models/`

```dart
// lib/models/topic.dart
class Topic {
  final int id;
  final String title;
  final DateTime? createdAt;

  const Topic({
    required this.id,
    required this.title,
    this.createdAt,
  });

  factory Topic.fromJson(Map<String, dynamic> json) { }
  Map<String, dynamic> toJson() { }
}
```

**枚举**：模型文件内或独立文件

```dart
// lib/models/topic.dart
enum TopicNotificationLevel {
  muted(0),
  regular(1),
  tracking(2),
  watching(3);

  const TopicNotificationLevel(this.value);
  final int value;

  static TopicNotificationLevel fromValue(int? value) {
    return TopicNotificationLevel.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TopicNotificationLevel.regular,
    );
  }
}
```

**类型别名**：`lib/utils/type_defs.dart`

```dart
typedef JsonMap = Map<String, dynamic>;
typedef TopicId = int;
typedef UserId = int;
```

---

## Validation

### 运行时类型检查

**fromJson 中验证类型**：

```dart
// lib/models/topic.dart
factory Topic.fromJson(Map<String, dynamic> json) {
  return Topic(
    id: json['id'] as int,  // 强制类型转换
    title: json['title'] as String? ?? '',  // 空值提供默认值
    createdAt: TimeUtils.parseUtcTime(json['created_at'] as String?),
  );
}
```

**列表类型转换**：

```dart
final tags = (json['tags'] as List<dynamic>?)
    ?.map((e) => Tag.fromJson(e))
    .toList() ?? const <Tag>[];
```

**Map 类型转换**：

```dart
final userMap = (json['users'] as List<dynamic>?)
    .map((u) => TopicUser.fromJson(u as Map<String, dynamic>))
    .toList();

final userMap = {
  for (var u in usersJson)
    (u['id'] as int): TopicUser.fromJson(u as Map<String, dynamic>)
};
```

---

## Common Patterns

### 1. 空值处理

**使用 `?` 可空类型**：

```dart
final String? excerpt;
final DateTime? createdAt;
```

**使用 `??` 提供默认值**：

```dart
final title = json['title'] as String? ?? '';
final count = json['count'] as int? ?? 0;
```

**使用 `?.` 安全调用**：

```dart
final name = user?.name ?? 'Unknown';
final avatarUrl = user?.avatarTemplate?.replaceAll('{size}', '40');
```

**避免使用 `!` 强制解包**：

```dart
// ❌ Bad: 可能崩溃
final user = currentUser!;

// ✅ Good: 安全处理
if (currentUser != null) {
  print(currentUser.name);
}
```

---

### 2. 类型转换

**使用 `as` 转换**：

```dart
final id = json['id'] as int;
final name = json['name'] as String? ?? '';
final items = json['items'] as List<dynamic>;
```

**复杂类型转换**：

```dart
final Map<String, dynamic> json = {
  'polls_votes': {
    'poll1': ['option1', 'option2'],
  },
};

final pollsVotes = (json['polls_votes'] as Map<String, dynamic>?)?.map(
  (key, value) => MapEntry(
    key,
    (value as List<dynamic>).map((e) => e.toString()).toList(),
  ),
);
```

---

### 3. 泛型

**使用泛型定义通用类型**：

```dart
class AsyncNotifier<T> {
  AsyncValue<T>? state;

  void update(T Function(T) updater) {
    final current = state?.value;
    if (current != null) {
      state = AsyncValue.data(updater(current));
    }
  }
}
```

**Provider 泛型**：

```dart
final topicDetailProvider = AsyncNotifierProvider.family<
  TopicDetailNotifier,
  TopicDetail?,
  int,  // 参数类型
>(TopicDetailNotifier.new);
```

---

### 4. 类型守卫

**检查类型后使用**：

```dart
void processData(dynamic data) {
  if (data is Map<String, dynamic>) {
    // 类型已确认，可以安全使用
    final id = data['id'] as int;
  } else if (data is List) {
    // 处理列表
    for (final item in data) {
      print(item);
    }
  }
}
```

---

## Forbidden Patterns

### 1. 禁止使用 `var` 声明类型

```dart
// ❌ Forbidden
var count = 10;
var user = User();
var topics = <Topic>[];

// ✅ Required
final int count = 10;
final User user = User();
final List<Topic> topics = <Topic>[];
```

---

### 2. 禁止使用 `dynamic`

```dart
// ❌ Forbidden
final data = json['data'] as dynamic;
void process(dynamic value) { }

// ✅ Required
final data = json['data'] as Map<String, dynamic>;
void process(Object? value) { }
```

**例外**：JSON 解析时允许 `Map<String, dynamic>`

```dart
// ✅ Allowed
factory Topic.fromJson(Map<String, dynamic> json) {
  return Topic(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
  );
}
```

---

### 3. 禁止强制解包 `!`（除非确定非空）

```dart
// ❌ Forbidden
final user = currentUser!;

// ✅ Required
if (currentUser != null) {
  print(currentUser.name);
}

// 或
final user = currentUser;
if (user != null) {
  print(user.name);
}
```

**例外**：测试中可以使用

```dart
// ✅ Allowed in tests
test('should parse json', () {
  final topic = Topic.fromJson({'id': 1, 'title': 'Test'});
  expect(topic.id, equals(1));  // topic 一定不为 null
});
```

---

### 4. 禁止忽略类型警告

```dart
// ❌ Forbidden
final list = [];  // Missing type annotation
final map = {};   // Missing type annotation

// ✅ Required
final List<Topic> list = [];
final Map<String, dynamic> map = {};
```

---

## Type Utilities

### 1. 使用 `Object?` 替代 `dynamic`

```dart
// ❌ Bad
void process(dynamic value) {
  if (value is String) {
    print(value);
  }
}

// ✅ Good
void process(Object? value) {
  if (value is String) {
    print(value);
  }
}
```

---

### 2. 使用类型别名提高可读性

```dart
typedef JsonMap = Map<String, dynamic>;
typedef TopicId = int;

Future<Topic> getTopic(TopicId id) async {
  final JsonMap json = await _dio.get('/t/$id.json');
  return Topic.fromJson(json);
}
```

---

### 3. 使用 `sealed` 类限制子类型

```dart
sealed class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

class Failure<T> extends Result<T> {
  final Object error;
  const Failure(this.error);
}
```

---

## Common Mistakes

### ❌ 使用 `var` 省略类型

```dart
var count = 10;  // 类型推断为 int
var user = fetchUser();  // 类型不明显
```

### ✅ 显式声明类型

```dart
final int count = 10;
final User user = await fetchUser();
```

---

### ❌ 忽略空值检查

```dart
final user = fetchUser();
print(user.name);  // user 可能为 null
```

### ✅ 处理空值

```dart
final user = await fetchUser();
if (user != null) {
  print(user.name);
}
```

---

### ❌ JSON 类型转换不当

```dart
final tags = json['tags'] as List<String>;  // 错误：实际是 List<dynamic>
```

### ✅ 正确转换

```dart
final tags = (json['tags'] as List<dynamic>)
    .cast<String>()
    .toList();
```

---

## Examples

### 良好的类型安全示例

**`lib/models/topic.dart`**：
- 明确的类型声明
- 完整的 fromJson/toJson 方法
- 空值安全处理
- 类型转换方法

**`lib/providers/core_providers.dart`**：
- Provider 泛型类型明确
- AsyncNotifier 类型参数清晰
- 返回类型明确

**`lib/utils/type_defs.dart`**：
- 类型别名定义
- 提高代码可读性
