# Directory Structure

> 如何组织 Flutter 项目中的服务层代码。

---

## Overview

本项目采用 Flutter + Riverpod 架构，服务层代码位于 `lib/services/` 目录，负责业务逻辑、网络请求、数据持久化等核心功能。

**核心原则**：
- 按功能领域组织服务，而非技术层
- 大型服务类使用 `part` 文件拆分
- 每个服务应单一职责，可测试

---

## Directory Layout

```
lib/services/
├── discourse/                 # Discourse API 服务（核心）
│   ├── discourse_service.dart # 主服务类
│   ├── _auth.dart             # 认证相关方法 (part 文件)
│   ├── _topics.dart           # 话题相关方法 (part 文件)
│   ├── _posts.dart            # 帖子相关方法 (part 文件)
│   ├── _users.dart            # 用户相关方法 (part 文件)
│   └── ...                    # 其他 part 文件
├── network/                   # 网络层
│   ├── adapters/              # HTTP 适配器（Cronet, Rhttp, WebView）
│   ├── cookie/                # Cookie 管理
│   ├── doh/                   # DNS over HTTPS
│   ├── doh_proxy/             # DoH 代理服务
│   ├── exceptions/            # 自定义异常
│   └── interceptors/          # Dio 拦截器
├── storage/                   # 数据持久化
├── background/                # 后台任务
├── log/                       # 日志服务
├── navigation/                # 导航服务
├── data_management/           # 数据管理（备份、缓存）
├── app_logger.dart            # 统一日志入口
├── auth_session.dart          # 认证会话管理
├── message_bus_service.dart   # Message Bus 服务
└── ...                        # 其他独立服务
```

---

## Module Organization

### 服务类组织原则

1. **单一职责**：每个服务只负责一个领域
   - `DiscourseService` - Discourse API 调用
   - `ConnectivityService` - 网络连接检测
   - `DownloadService` - 文件下载管理

2. **大型服务拆分**：使用 `part` 文件组织
   ```dart
   // discourse_service.dart
   part '_auth.dart';
   part '_topics.dart';
   part '_posts.dart';

   class DiscourseService extends _DiscourseServiceBase
       with _AuthMixin, _TopicsMixin, _PostsMixin {
     // 共享字段和核心逻辑
   }

   // _topics.dart
   part of 'discourse_service.dart';

   mixin _TopicsMixin on _DiscourseServiceBase {
     Future<TopicDetail> getTopic(int topicId) async { ... }
   }
   ```

3. **功能模块化**：复杂功能独立为子目录
   ```
   network/
   ├── cookie/              # Cookie 管理子系统
   │   ├── strategy/        # 平台特定策略
   │   └── ...
   └── doh_proxy/           # DoH 代理子系统
       ├── doh_proxy.dart
       ├── doh_proxy_service.dart
       └── ...
   ```

---

## Naming Conventions

### 文件命名

- **服务文件**：`<domain>_service.dart`
  - 示例：`download_service.dart`, `auth_session.dart`

- **Part 文件**：`_<feature>.dart` (下划线前缀)
  - 示例：`_auth.dart`, `_topics.dart`

- **目录命名**：小写下划线 (snake_case)
  - 示例：`network/`, `doh_proxy/`, `data_management/`

### 类命名

- **服务类**：`<Domain>Service`
  - 示例：`DiscourseService`, `DownloadService`

- **Mixin**：`_<Feature>Mixin` (私有前缀)
  - 示例：`_AuthMixin`, `_TopicsMixin`

- **异常类**：描述性名称 + `Exception`
  - 示例：`RateLimitException`, `ServerException`

---

## Examples

### 良好的服务组织示例

**`lib/services/discourse/discourse_service.dart`**：
- 主服务类定义共享字段和依赖注入
- 使用 `part` 文件按功能拆分（认证、话题、帖子、用户等）
- Mixin 模式实现代码复用

**`lib/services/network/`**：
- 按功能分层：`adapters/`, `cookie/`, `exceptions/`, `interceptors/`
- 每个子目录独立管理复杂子系统

**`lib/services/app_logger.dart`**：
- 简单服务单文件实现
- 提供统一的日志 API

---

## Common Mistakes

### 错误示例

**❌ 在一个文件中实现所有功能**：
```dart
// bad: discourse_service.dart 包含 2000+ 行代码
class DiscourseService {
  // 认证、话题、帖子、用户...所有方法混在一起
}
```

**✅ 正确：使用 part 文件拆分**：
```dart
// discourse_service.dart (< 200 行)
part '_auth.dart';
part '_topics.dart';

class DiscourseService extends _DiscourseServiceBase
    with _AuthMixin, _TopicsMixin { ... }
```

---

**❌ 服务职责不清**：
```dart
// bad: 一个服务既负责网络请求又负责 UI 逻辑
class TopicService {
  Future<Topic> fetchTopic() { ... }
  void showTopicCard(BuildContext context) { ... } // 不应属于服务层
}
```

**✅ 正确：服务只负责业务逻辑**：
```dart
// good: 服务只处理数据获取
class TopicService {
  Future<Topic> fetchTopic() { ... }
}

// UI 逻辑放在 Provider 或 Widget 中
```

---

**❌ 硬编码依赖**：
```dart
// bad: 硬编码 Dio 实例
class MyService {
  final _dio = Dio(); // 无法测试，无法替换
}
```

**✅ 正确：通过构造函数注入依赖**：
```dart
// good: 依赖注入
class MyService {
  final Dio _dio;
  MyService(this._dio);
}

// 或通过 Provider 注入
final myServiceProvider = Provider((ref) => MyService(ref.watch(dioProvider)));
```
