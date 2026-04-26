# Directory Structure

> Flutter 项目前端代码组织结构。

---

## Overview

本项目采用 Flutter + Riverpod 架构，前端代码位于 `lib/` 目录，遵循清晰的功能分层和模块化组织。

**核心原则**：
- 按功能分层：models, providers, services, widgets, pages
- Widget 可复用：通用 widget 放在 `widgets/common/`
- Page 独立：每个页面一个文件，复杂页面使用子目录

---

## Directory Layout

```
lib/
├── main.dart                  # 应用入口
├── constants.dart             # 全局常量
├── config/                    # 配置文件
│   └── sites/                 # 站点配置
├── l10n/                      # 国际化
│   ├── app_localizations.dart # 本地化基类
│   ├── app_localizations_zh.dart
│   ├── app_localizations_en.dart
│   └── s.dart                 # 简化访问接口
├── models/                    # 数据模型
│   ├── topic.dart
│   ├── user.dart
│   └── ...
├── providers/                 # 状态管理（Riverpod）
│   ├── core_providers.dart    # 核心服务 Provider
│   ├── discourse_providers.dart
│   ├── topic_detail_provider.dart
│   ├── message_bus/           # Message Bus 子系统
│   └── topic_list/            # 话题列表子状态
├── services/                  # 业务逻辑层
│   ├── discourse/             # Discourse API
│   ├── network/               # 网络层
│   ├── storage/               # 数据持久化
│   └── ...
├── widgets/                   # 可复用组件
│   ├── common/                # 通用组件（按钮、卡片、对话框）
│   ├── topic/                 # 话题相关组件
│   ├── post/                  # 帖子相关组件
│   ├── user/                  # 用户相关组件
│   └── content/               # 内容渲染组件
├── pages/                     # 页面
│   ├── settings_page.dart     # 设置页
│   ├── topic_detail_page/     # 复杂页面使用子目录
│   │   ├── topic_detail_page.dart
│   │   ├── controllers/
│   │   └── widgets/
│   └── ...
├── utils/                     # 工具函数
│   ├── time_utils.dart        # 时间处理
│   ├── url_helper.dart        # URL 解析
│   └── ...
├── settings/                  # 设置系统
│   ├── definitions/           # 设置项定义
│   ├── settings_model.dart
│   └── settings_renderer.dart
└── navigation/                # 导航系统
    ├── nav_entry.dart
    └── nav_entry_registry.dart
```

---

## Module Organization

### Models - 数据模型层

**职责**：
- 定义数据结构
- 提供 `fromJson` / `toCacheJson` 工厂方法
- 实现 `copyWith` 支持不可变更新

**示例**：

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

  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      createdAt: TimeUtils.parseUtcTime(json['created_at'] as String?),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'id': id,
      'title': title,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  Topic copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
  }) {
    return Topic(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
```

---

### Providers - 状态管理层

**职责**：
- 管理应用状态
- 协调 Service 和 UI
- 处理异步加载、缓存、刷新

**Provider 类型**：

```dart
// 服务 Provider
final discourseServiceProvider = Provider((ref) => DiscourseService());

// 异步数据 Provider
final currentUserProvider = AsyncNotifierProvider<CurrentUserNotifier, User?>(
  CurrentUserNotifier.new,
);

// 计算属性 Provider
final categoryMapProvider = FutureProvider<Map<int, Category>?>((ref) async {
  final service = ref.watch(discourseServiceProvider);
  return service.getCategoryMap();
});
```

**示例**：

```dart
// lib/providers/topic_detail_provider.dart
class TopicDetailNotifier extends AsyncNotifier<TopicDetail?> {
  @override
  Future<TopicDetail?> build(int topicId) async {
    return _loadTopic(topicId);
  }

  Future<TopicDetail> _loadTopic(int topicId) async {
    final service = ref.read(discourseServiceProvider);
    return await service.getTopic(topicId);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadTopic(topicId));
  }
}

final topicDetailProvider = AsyncNotifierProvider.family<TopicDetailNotifier, TopicDetail?, int>(
  TopicDetailNotifier.new,
);
```

---

### Widgets - 可复用组件层

**组织原则**：
- `widgets/common/` - 通用组件（不依赖业务逻辑）
- `widgets/<domain>/` - 业务组件（依赖特定模型）

**通用组件示例**：

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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 16),
          Text(error.toString()),
          if (onRetry != null)
            ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
```

**业务组件示例**：

```dart
// lib/widgets/topic/topic_card.dart
class TopicCard extends ConsumerWidget {
  final Topic topic;
  final VoidCallback? onTap;

  const TopicCard({
    super.key,
    required this.topic,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryMap = ref.watch(categoryMapProvider).value;
    final category = categoryMap?[int.tryParse(topic.categoryId)];

    return Card(
      child: ListTile(
        title: Text(topic.title),
        subtitle: Text(category?.name ?? ''),
        onTap: onTap,
      ),
    );
  }
}
```

---

### Pages - 页面层

**职责**：
- 页面级别的 UI 结构
- 组合 Widget 和 Provider
- 处理页面导航和生命周期

**简单页面**：单文件

```dart
// lib/pages/settings_page.dart
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(title: const Text('外观'), onTap: () => ...),
          ListTile(title: const Text('网络'), onTap: () => ...),
        ],
      ),
    );
  }
}
```

**复杂页面**：使用子目录

```
topic_detail_page/
├── topic_detail_page.dart      # 主页面
├── controllers/                # 页面控制器
│   └── topic_detail_controller.dart
├── widgets/                    # 页面专用组件
│   ├── ai_chat_guide.dart
│   └── ...
└── actions/                    # 页面动作
    ├── _filter_actions.dart
    └── _scroll_actions.dart
```

---

## Naming Conventions

### 文件命名

- **Model**：`<entity>.dart`
  - 示例：`topic.dart`, `user.dart`

- **Provider**：`<domain>_provider.dart`
  - 示例：`topic_detail_provider.dart`, `user_provider.dart`

- **Widget**：`<purpose>_<type>.dart`
  - 示例：`topic_card.dart`, `error_view.dart`

- **Page**：`<purpose>_page.dart`
  - 示例：`settings_page.dart`, `topic_detail_page.dart`

### 类命名

- **Model**：PascalCase，单数
  - 示例：`Topic`, `User`, `Category`

- **Widget**：PascalCase，描述性名称
  - 示例：`TopicCard`, `ErrorView`, `SmartAvatar`

- **Page**：`<Purpose>Page`
  - 示例：`SettingsPage`, `TopicDetailPage`

- **Provider Notifier**：`<Entity>Notifier`
  - 示例：`CurrentUserNotifier`, `TopicDetailNotifier`

---

## Common Mistakes

### ❌ 在 Widget 文件中定义 Provider

```dart
// bad: topic_card.dart
class TopicCard extends ConsumerWidget { }

final topicCardProvider = Provider(...);  // 不应放在这里
```

### ✅ 正确：Provider 放在 providers/ 目录

```
providers/
└── topic_card_provider.dart  # Provider 单独文件
```

---

### ❌ 在 Page 中定义可复用 Widget

```dart
// bad: settings_page.dart
class SettingsPage extends StatelessWidget { }

class _SettingsListItem extends StatelessWidget { }  // 可复用组件不应作为私有类
```

### ✅ 正确：可复用 Widget 放在 widgets/

```
widgets/
└── settings/
    └── settings_list_item.dart
```

---

### ❌ Provider 文件过大

```dart
// bad: topic_provider.dart 包含所有话题相关 Provider（500+ 行）
final topicListProvider = ...;
final topicDetailProvider = ...;
final topicSearchProvider = ...;
```

### ✅ 正确：按功能拆分

```
providers/
├── topic_list/
│   └── topic_list_provider.dart
├── topic_detail_provider.dart
└── topic_search_provider.dart
```

---

## Examples

### 良好的目录组织示例

**`lib/widgets/content/discourse_html_content/`**：
- 复杂组件使用子目录
- 按功能分类：`builders/`, `callout/`, `chunked/`
- 主文件 `discourse_html_content.dart` 导出公共接口

**`lib/providers/message_bus/`**：
- 子系统独立目录
- 包含模型、Provider、服务
- 清晰的职责分离

**`lib/pages/topic_detail_page/`**：
- 复杂页面拆分为子目录
- 控制器、组件、动作分离
- 易于维护和扩展
