# Component Guidelines

> Flutter 组件开发规范。

---

## Overview

本项目使用 Flutter Widget 构建UI，遵循 StatelessWidget 优先、状态提升、组合优于继承的原则。

**核心原则**：
- 优先使用 `StatelessWidget`
- 使用 `ConsumerWidget` 访问 Provider
- Widget 参数使用 `final` 不可变字段
- 复杂组件拆分为小组件组合

---

## Component Structure

### StatelessWidget 结构

```dart
// lib/widgets/common/error_view.dart
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            error.toString(),
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}
```

---

### ConsumerWidget 结构

```dart
// lib/widgets/topic/topic_card.dart
class TopicCard extends ConsumerWidget {
  final Topic topic;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  const TopicCard({
    super.key,
    required this.topic,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categoryMap = ref.watch(categoryMapProvider).value;
    final category = categoryMap?[int.tryParse(topic.categoryId)];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, category),
              const SizedBox(height: 8),
              _buildTitle(context),
              const SizedBox(height: 6),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Category? category) {
    return Row(
      children: [
        if (category != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Color(int.parse('0xFF${category.color}')),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              category.name,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            topic.lastPosterUsername ?? '',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Text(
      topic.title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.remove_red_eye, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text('${topic.views}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 12),
        Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text('${topic.postsCount}', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
```

---

## Props Conventions

### 参数定义规则

**必填参数使用 `required`**：

```dart
class TopicCard extends StatelessWidget {
  final Topic topic;  // 必填
  final VoidCallback? onTap;  // 可选

  const TopicCard({
    super.key,
    required this.topic,  // required
    this.onTap,  // 可选
  });
}
```

**布尔参数提供默认值**：

```dart
class TopicCard extends StatelessWidget {
  final bool isSelected;

  const TopicCard({
    super.key,
    required this.topic,
    this.isSelected = false,  // 默认值
  });
}
```

**可选参数使用 `?` 类型**：

```dart
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;  // 可选回调
  final Color? backgroundColor;  // 可选样式

  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.backgroundColor,
  });
}
```

---

### 参数命名规范

| 类型 | 命名 | 示例 |
|------|------|------|
| 回调 | `on<Action>` | `onTap`, `onPressed`, `onLongPress` |
| 控制器 | `controller` | `controller`, `scrollController` |
| 数据模型 | 实体名称 | `topic`, `user`, `post` |
| 样式 | 描述性名称 | `backgroundColor`, `borderRadius` |
| 布尔状态 | `is<State>` | `isSelected`, `isLoading`, `isVisible` |

---

## Styling Patterns

### 使用 Theme

```dart
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  
  return Text(
    topic.title,
    style: theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    ),
  );
}
```

### 避免硬编码颜色

```dart
// ❌ Bad
Container(color: Color(0xFF2196F3))

// ✅ Good
Container(color: Theme.of(context).colorScheme.primary)
```

### 使用 EdgeInsets

```dart
// ✅ Good
Padding(
  padding: const EdgeInsets.all(12),  // 四周相同
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),  // 水平/垂直
  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),  // 分别指定
  child: ...,
)
```

---

## Accessibility

### 语义标签

```dart
IconButton(
  icon: const Icon(Icons.settings),
  onPressed: () => ...,
  tooltip: '设置',  // 长按显示提示
)
```

### 可点击区域

```dart
// 最小点击区域 48x48
InkWell(
  onTap: () => ...,
  child: Container(
    width: 48,
    height: 48,
    alignment: Alignment.center,
    child: const Icon(Icons.add, size: 24),
  ),
)
```

---

## Common Mistakes

### ❌ 在 StatelessWidget 中使用可变字段

```dart
class TopicCard extends StatelessWidget {
  String title;  // bad: 可变字段

  TopicCard({required this.title});
}
```

### ✅ 正确：所有字段都是 final

```dart
class TopicCard extends StatelessWidget {
  final String title;  // good: 不可变

  const TopicCard({required this.title});
}
```

---

### ❌ 过度使用 StatefulWidget

```dart
// bad: 简单组件不需要 StatefulWidget
class UserAvatar extends StatefulWidget {
  final String url;

  UserAvatar({required this.url});
}

class _UserAvatarState extends State<UserAvatar> {
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(backgroundImage: NetworkImage(widget.url));
  }
}
```

### ✅ 正确：优先使用 StatelessWidget

```dart
// good: 无状态组件
class UserAvatar extends StatelessWidget {
  final String url;

  const UserAvatar({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(backgroundImage: NetworkImage(url));
  }
}
```

---

### ❌ 在 Widget 中直接调用网络请求

```dart
class TopicList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // bad: Widget 不应直接调用网络请求
    final topics = await DiscourseService().getTopics();
    return ListView(...);
  }
}
```

### ✅ 正确：通过 Provider 获取数据

```dart
class TopicList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // good: 通过 Provider 获取数据
    final topicsAsync = ref.watch(topicListProvider);
    
    return topicsAsync.when(
      data: (topics) => ListView.builder(...),
      loading: () => const CircularProgressIndicator(),
      error: (e, st) => ErrorView(error: e),
    );
  }
}
```

---

### ❌ 忽略 Theme 直接硬编码样式

```dart
Text(
  '标题',
  style: TextStyle(
    fontSize: 16,
    color: Colors.black,
    fontWeight: FontWeight.bold,
  ),
)
```

### ✅ 正确：使用 Theme

```dart
Text(
  '标题',
  style: Theme.of(context).textTheme.titleMedium?.copyWith(
    fontWeight: FontWeight.bold,
  ),
)
```

---

## Examples

### 良好的组件示例

**`lib/widgets/common/smart_avatar.dart`**：
- 清晰的参数定义
- 使用 Theme 而非硬编码
- 支持多种尺寸和样式
- 可访问性支持（语义标签）

**`lib/widgets/topic/topic_card.dart`**：
- ConsumerWidget 访问 Provider
- 拆分为多个私有方法组织代码
- 参数命名清晰，提供默认值
- 使用 const 构造函数

**`lib/widgets/common/relative_time_text.dart`**：
- StatelessWidget 简单组件
- 工具类集成（TimeUtils）
- 支持自定义样式
