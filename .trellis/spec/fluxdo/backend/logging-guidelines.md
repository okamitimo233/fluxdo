# Logging Guidelines

> 项目日志规范。

---

## Overview

本项目使用统一的日志入口 `AppLogger`，支持分级日志、文件持久化、错误追踪集成。

**核心原则**：
- 使用 `AppLogger` 统一接口，不直接使用 `print()` 或 `debugPrint()`
- 日志消息应清晰描述事件，包含关键上下文
- 错误日志必须包含异常对象和堆栈信息

---

## Log Levels

### INFO - 信息级别

**用途**：
- 关键业务事件（登录成功、数据加载完成）
- 用户操作记录（打开设置页、切换主题）
- 网络请求成功

**示例**：

```dart
// 用户登录成功
AppLogger.info('用户登录成功', tag: 'Auth');

// 数据加载完成
AppLogger.info('加载话题列表成功: ${topics.length} 条', tag: 'TopicList');

// 缓存命中
AppLogger.info('使用缓存的用户数据', tag: 'UserProvider');
```

**输出**：
```
[Auth] 用户登录成功
[TopicList] 加载话题列表成功: 20 条
```

---

### WARNING - 警告级别

**用途**：
- 可恢复的异常情况（缓存损坏、降级处理）
- 性能问题（请求超时、慢查询）
- 废弃 API 调用

**示例**：

```dart
// 缓存损坏，降级到网络请求
try {
  final cached = prefs.getString('user_cache');
  return User.fromCacheJson(jsonDecode(cached));
} catch (e) {
  AppLogger.warning('用户缓存损坏，从网络重新加载', tag: 'UserProvider');
  return await _loadFromNetwork();
}

// 请求超时但已重试成功
AppLogger.warning('请求超时，已自动重试', tag: 'Network');
```

**输出**：
```
[WARN] [UserProvider] 用户缓存损坏，从网络重新加载
```

---

### ERROR - 错误级别

**用途**：
- 严重错误（网络失败、认证失败）
- 未捕获的异常
- 需要用户干预的错误

**示例**：

```dart
// 网络请求失败
try {
  await discourseService.getTopic(topicId);
} catch (e, st) {
  AppLogger.error(
    '加载话题失败: $topicId',
    tag: 'TopicDetail',
    error: e,
    stackTrace: st,
  );
  rethrow;
}

// 认证失败
try {
  await discourseService.login(username, password);
} catch (e, st) {
  AppLogger.error('登录失败', tag: 'Auth', error: e, stackTrace: st);
  showDialog(context: context, builder: (_) => ErrorDialog(message: '登录失败'));
}
```

**输出**：
```
[ERROR] [TopicDetail] 加载话题失败: 12345
  Error: DioException [bad response]: ... 
  StackTrace: ...
```

---

## Logging Structure

### 统一日志入口

```dart
// lib/services/app_logger.dart
class AppLogger {
  AppLogger._();

  static bool _enabled = true;

  /// 信息级别日志（控制台 + 文件）
  static void info(String message, {String? tag}) {
    if (!_enabled) return;

    if (kDebugMode) {
      debugPrint(_format('INFO', tag, message));
    }

    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'info',
      'type': 'general',
      'message': message,
      if (tag != null) 'tag': tag,
    });
  }

  /// 警告级别日志（控制台 + 文件）
  static void warning(String message, {String? tag}) {
    if (!_enabled) return;

    if (kDebugMode) {
      debugPrint(_format('WARN', tag, message));
    }

    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'warning',
      'type': 'general',
      'message': message,
      if (tag != null) 'tag': tag,
    });
  }

  /// 错误级别日志（控制台 + 文件 + Catcher2）
  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_enabled) return;

    if (kDebugMode) {
      debugPrint(_format('ERROR', tag, message));
      if (error != null) debugPrint('  Error: $error');
      if (stackTrace != null) debugPrint('  StackTrace: $stackTrace');
    }

    Catcher2.reportCheckedError(
      error ?? message,
      stackTrace ?? StackTrace.current,
      extraData: {
        if (tag != null) 'tag': tag,
        'message': message,
      },
    );
  }

  static String _format(String level, String? tag, String message) {
    if (tag != null) {
      return '[$tag] $message';
    }
    return '[$level] $message';
  }
}
```

---

### 日志文件格式

**JSON Lines 格式**（每行一个 JSON 对象）：

```json
{"timestamp":"2024-01-15T14:30:25.123Z","level":"info","tag":"Auth","message":"用户登录成功"}
{"timestamp":"2024-01-15T14:30:26.456Z","level":"error","tag":"Network","message":"请求失败","error":"DioException: ..."}
```

**优势**：
- 易于解析和查询
- 支持日志分析工具（如 ELK Stack）
- 可按需导出和上传

---

## File Storage

### 日志文件位置

```dart
// lib/services/log/log_writer.dart
class LogWriter {
  static final LogWriter instance = LogWriter._();
  File? _logFile;

  Future<File> _getLogFile() async {
    if (_logFile != null) return _logFile!;
    
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    
    // 按日期分割日志文件
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _logFile = File('${logDir.path}/app_$date.jsonl');
    return _logFile!;
  }

  Future<void> write(Map<String, dynamic> log) async {
    final file = await _getLogFile();
    final content = jsonEncode(log) + '\n';
    await file.writeAsString(content, mode: FileMode.append);
  }
}
```

**文件结构**：
```
<Documents>/
└── logs/
    ├── app_2024-01-15.jsonl
    ├── app_2024-01-16.jsonl
    └── app_2024-01-17.jsonl
```

---

## Tag Conventions

### 推荐的 Tag 命名

| Tag | 用途 | 示例 |
|-----|------|------|
| `Auth` | 认证相关 | 登录、退出、令牌刷新 |
| `Network` | 网络请求 | HTTP 请求、重试、超时 |
| `TopicList` | 话题列表 | 加载、刷新、过滤 |
| `TopicDetail` | 话题详情 | 帖子加载、回复 |
| `UserProvider` | 用户状态 | 用户信息、缓存 |
| `Cache` | 缓存管理 | 命中、失效、清除 |
| `Settings` | 设置 | 配置变更、持久化 |
| `Notification` | 通知 | 推送、本地通知 |

---

## Common Mistakes

### ❌ 使用 print() 或 debugPrint()

```dart
// bad: 不统一的日志格式，无法持久化
print('用户登录成功');
debugPrint('[Auth] 登录失败: $error');
```

### ✅ 正确：使用 AppLogger

```dart
AppLogger.info('用户登录成功', tag: 'Auth');
AppLogger.error('登录失败', tag: 'Auth', error: error);
```

---

### ❌ 日志消息不清晰

```dart
// bad: 没有上下文信息
AppLogger.info('加载成功', tag: 'Data');
AppLogger.error('失败', tag: 'Network');
```

### ✅ 正确：包含关键信息

```dart
AppLogger.info('加载话题列表成功: 20 条', tag: 'TopicList');
AppLogger.error('加载话题失败: ID=$topicId', tag: 'TopicDetail', error: e);
```

---

### ❌ 错误日志缺少堆栈信息

```dart
// bad: 无法追踪错误位置
AppLogger.error('网络请求失败', tag: 'Network');
```

### ✅ 正确：包含异常对象和堆栈

```dart
try {
  await fetchData();
} catch (e, st) {
  AppLogger.error('网络请求失败', tag: 'Network', error: e, stackTrace: st);
}
```

---

### ❌ 在生产环境泄露敏感信息

```dart
// bad: 日志包含密码、令牌
AppLogger.info('用户登录: $username, 密码: $password', tag: 'Auth');
AppLogger.info('Token: $token', tag: 'Network');
```

### ✅ 正确：脱敏处理

```dart
AppLogger.info('用户登录: $username', tag: 'Auth');
AppLogger.info('Token 已更新', tag: 'Network');
```

---

### ❌ 日志过于频繁

```dart
// bad: 每个帖子渲染都记录日志
Widget buildPost(Post post) {
  AppLogger.info('渲染帖子: ${post.id}', tag: 'UI');
  return PostCard(post: post);
}
```

### ✅ 正确：只记录关键事件

```dart
// 只在批量加载完成时记录
Future<void> loadPosts() async {
  final posts = await fetchPosts();
  AppLogger.info('加载帖子成功: ${posts.length} 条', tag: 'TopicDetail');
}
```

---

## Log Viewing

### 查看日志文件

**在应用内查看**：

```dart
// lib/pages/app_logs_page.dart
// 提供日志查看器 UI，支持：
// - 按日期筛选
// - 按级别筛选
// - 搜索关键词
// - 导出日志文件
```

**导出日志**：

```dart
final logFile = await LogWriter.instance.getCurrentLogFile();
await Share.shareXFiles([XFile(logFile.path)], text: '应用日志');
```

---

## Performance

### 异步写入，不阻塞主线程

```dart
// LogWriter 使用 fire-and-forget 模式
Future<void> write(Map<String, dynamic> log) async {
  // 不等待写入完成
  unawaited(_writeToFile(log));
}

Future<void> _writeToFile(Map<String, dynamic> log) async {
  final file = await _getLogFile();
  await file.writeAsString(jsonEncode(log) + '\n', mode: FileMode.append);
}
```

### 日志开关

```dart
// 在生产环境可关闭详细日志
if (kReleaseMode) {
  AppLogger.setEnabled(false);
}
```
