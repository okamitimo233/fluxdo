# Quality Guidelines

> 前端代码质量标准。

---

## Overview

本项目遵循 Flutter 最佳实践，强调代码可读性、可维护性和性能优化。

**核心原则**：
- StatelessWidget 优先
- 使用 const 构造函数
- 避免 unnecessary rebuild
- 国际化所有用户可见文本

---

## Forbidden Patterns

### 1. 禁止使用 `var` 声明类型

```dart
// ❌ Forbidden
var count = 10;
var user = User();

// ✅ Required
final int count = 10;
final User user = User();
```

---

### 2. 禁止在 Widget 中直接调用网络请求

```dart
// ❌ Forbidden
class TopicList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final topics = await DiscourseService().getTopics();  // 禁止
    return ListView(...);
  }
}

// ✅ Required
class TopicList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicsAsync = ref.watch(topicListProvider);
    return topicsAsync.when(...);
  }
}
```

---

### 3. 禁止硬编码颜色和字符串

```dart
// ❌ Forbidden
Container(color: Color(0xFF2196F3))
Text('Settings')

// ✅ Required
Container(color: Theme.of(context).colorScheme.primary)
Text(S.current.settings_title)
```

---

### 4. 禁止使用 `print()` 调试

```dart
// ❌ Forbidden
print('User logged in: $username');

// ✅ Required
AppLogger.info('用户登录成功', tag: 'Auth');
```

---

### 5. 禁止在 StatelessWidget 中使用可变字段

```dart
// ❌ Forbidden
class TopicCard extends StatelessWidget {
  String title;  // 可变字段

  TopicCard({required this.title});
}

// ✅ Required
class TopicCard extends StatelessWidget {
  final String title;  // 不可变

  const TopicCard({super.key, required this.title});
}
```

---

## Required Patterns

### 1. 必须使用 `const` 构造函数

```dart
// ✅ Required
class TopicCard extends StatelessWidget {
  final Topic topic;

  const TopicCard({  // const 构造函数
    super.key,
    required this.topic,
  });
}
```

---

### 2. 必须处理 AsyncValue 的所有状态

```dart
// ✅ Required
final userAsync = ref.watch(currentUserProvider);

return userAsync.when(
  data: (user) => Text(user?.name ?? 'Guest'),
  loading: () => const CircularProgressIndicator(),
  error: (e, st) => ErrorView(error: e),
);
```

---

### 3. 必须使用 Theme 而非硬编码样式

```dart
// ✅ Required
Text(
  topic.title,
  style: Theme.of(context).textTheme.titleMedium?.copyWith(
    fontWeight: FontWeight.w600,
  ),
)
```

---

### 4. 必须提供 Widget key

```dart
// ✅ Required
TopicCard(
  key: ValueKey(topic.id),  // 提供唯一 key
  topic: topic,
)
```

---

### 5. 必须在 dispose 中清理资源

```dart
// ✅ Required
class _MyState extends State<MyWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();  // 清理资源
    super.dispose();
  }
}
```

---

## Testing Requirements

### Widget 测试

**必须测试**：
- Widget 是否正常渲染
- 不同状态下的 UI 表现
- 用户交互（点击、输入）

**示例**：

```dart
testWidgets('TopicCard displays title', (tester) async {
  final topic = Topic(id: 1, title: 'Test Topic');

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TopicCard(topic: topic),
    ),
  ));

  expect(find.text('Test Topic'), findsOneWidget);
});
```

---

### Provider 测试

**必须测试**：
- Provider 初始状态
- 状态更新逻辑
- 异步加载和错误处理

**示例**：

```dart
test('CurrentUserNotifier loads user', () async {
  final container = ProviderContainer();

  final user = await container.read(currentUserProvider.future);
  expect(user, isNotNull);

  container.dispose();
});
```

---

## Code Review Checklist

### Widget 检查项

- [ ] Widget 使用 `const` 构造函数
- [ ] 所有字段使用 `final`
- [ ] 参数命名清晰，提供默认值
- [ ] 使用 Theme 而非硬编码样式
- [ ] 使用国际化字符串
- [ ] 提供 Widget key
- [ ] 处理 AsyncValue 的所有状态
- [ ] dispose 中清理资源

---

### Provider 检查项

- [ ] 使用适当的 Provider 类型
- [ ] 处理加载和错误状态
- [ ] 使用 `select` 优化性能
- [ ] 缓存策略合理
- [ ] 提供 refresh 方法
- [ ] 不直接修改状态，通过 Notifier 方法

---

### 代码质量检查项

- [ ] 无 `print()` 或 `debugPrint()`
- [ ] 使用 AppLogger 记录日志
- [ ] 无硬编码字符串和颜色
- [ ] 无 `var` 类型声明
- [ ] 无 `dynamic` 类型（必要时使用 `Object?`）
- [ ] 函数单一职责，命名清晰
- [ ] 无嵌套过深的 if-else

---

## Performance Checklist

### 避免不必要的 rebuild

```dart
// ✅ Good: 使用 select
final name = ref.watch(currentUserProvider.select((user) => user?.name));

// ❌ Bad: 整个对象变化都 rebuild
final user = ref.watch(currentUserProvider);
return Text(user.value?.name ?? '');
```

---

### 使用 const Widget

```dart
// ✅ Good: const Widget 不重建
return const Text('Hello');

// ❌ Bad: 每次都创建新实例
return Text('Hello');
```

---

### 延迟加载

```dart
// ✅ Good: 使用 ListView.builder 懒加载
ListView.builder(
  itemCount: topics.length,
  itemBuilder: (context, index) => TopicCard(topic: topics[index]),
)

// ❌ Bad: 一次性渲染所有
Column(
  children: topics.map((t) => TopicCard(topic: t)).toList(),
)
```

---

## Common Mistakes

### ❌ 忘记 const 构造函数

```dart
class TopicCard extends StatelessWidget {
  TopicCard({required this.topic});  // 缺少 const
}
```

### ✅ 正确

```dart
class TopicCard extends StatelessWidget {
  const TopicCard({super.key, required this.topic});  // 添加 const
}
```

---

### ❌ 不处理错误状态

```dart
final user = ref.watch(currentUserProvider);
return Text(user.value?.name ?? '');  // 忽略 loading 和 error
```

### ✅ 正确

```dart
final userAsync = ref.watch(currentUserProvider);
return userAsync.when(
  data: (user) => Text(user?.name ?? 'Guest'),
  loading: () => const CircularProgressIndicator(),
  error: (e, st) => ErrorView(error: e),
);
```

---

### ❌ 过度使用 StatefulWidget

```dart
class UserAvatar extends StatefulWidget {  // 无状态组件不需要 StatefulWidget
  final String url;
  UserAvatar({required this.url});
}
```

### ✅ 正确

```dart
class UserAvatar extends StatelessWidget {  // 使用 StatelessWidget
  final String url;
  const UserAvatar({super.key, required this.url});
}
```
