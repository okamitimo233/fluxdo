# Error Handling

> 项目中的错误处理规范。

---

## Overview

本项目使用自定义异常类明确区分错误类型，结合 Dio 异常处理机制，实现清晰的错误传播和用户提示。

**核心原则**：
- 使用明确的异常类型，而非泛型 `Exception`
- 服务层捕获底层异常并转换为领域异常
- 所有异常包含用户友好的错误消息

---

## Error Types

### 业务异常（定义在 `lib/services/network/exceptions/api_exception.dart`）

```dart
/// 429 Rate Limit 异常（重试耗尽后抛出）
class RateLimitException implements Exception {
  final int? retryAfterSeconds;
  final String? message;

  RateLimitException([this.retryAfterSeconds, this.message]);

  @override
  String toString() => message ?? S.current.error_rateLimitedRetryLater;
}

/// 服务器错误异常（502/503/504 重试耗尽后抛出）
class ServerException implements Exception {
  final int statusCode;
  ServerException(this.statusCode);

  @override
  String toString() => '${S.current.error_serviceUnavailableRetry} ($statusCode)';
}

/// 帖子进入审核队列异常
class PostEnqueuedException implements Exception {
  final int pendingCount;
  PostEnqueuedException({this.pendingCount = 0});

  @override
  String toString() => S.current.network_postPendingReview;
}

/// Cloudflare 验证异常
class CfChallengeException implements Exception {
  final bool userCancelled;
  final bool inCooldown;
  final Object? cause; // 原始错误（用于调试）

  CfChallengeException({
    this.userCancelled = false,
    this.inCooldown = false,
    this.cause,
  });

  @override
  String toString() {
    if (inCooldown) return S.current.cf_cooldown;
    if (userCancelled) return S.current.cf_userCancelled;
    if (cause != null) return S.current.cf_failedWithCause('$cause');
    return S.current.cf_failedRetry;
  }
}
```

### 使用场景

| 异常类型 | 触发场景 | 用户提示 |
|---------|---------|---------|
| `RateLimitException` | 请求频率超限且重试耗尽 | "请求过于频繁，请稍后再试" |
| `ServerException` | 服务器错误（502/503/504）| "服务暂时不可用，请稍后重试" |
| `PostEnqueuedException` | 帖子进入审核队列 | "帖子需要审核后才能发布" |
| `CfChallengeException` | Cloudflare 验证失败 | "验证失败，请重试" |

---

## Error Handling Patterns

### 1. 服务层：捕获并转换异常

```dart
// lib/services/discourse/_topics.dart
Future<TopicDetail> getTopic(int topicId) async {
  try {
    final response = await _dio.get('/t/$topicId.json');
    return TopicDetail.fromJson(response.data);
  } on DioException catch (e) {
    // 转换 Dio 异常为业务异常
    if (e.response?.statusCode == 404) {
      throw Exception('话题不存在');
    }
    throw _handleDioError(e); // 统一异常处理方法
  }
}
```

### 2. 统一异常处理方法

```dart
// lib/services/discourse/_utils.dart
Exception _handleDioError(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return Exception(S.current.error_networkTimeout);
    
    case DioExceptionType.badResponse:
      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        return Exception(S.current.error_unauthorized);
      }
      if (statusCode == 429) {
        final retryAfter = error.response?.headers['retry-after'];
        return RateLimitException(
          int.tryParse(retryAfter?.first ?? ''),
          S.current.error_rateLimitedRetryLater,
        );
      }
      if (statusCode! >= 500) {
        return ServerException(statusCode);
      }
      return Exception(S.current.error_serverError(statusCode));
    
    default:
      return Exception(S.current.error_networkError);
  }
}
```

### 3. Provider 层：优雅处理异常

```dart
// lib/providers/topic_detail_provider.dart
Future<TopicDetail> _loadTopic(int topicId) async {
  try {
    return await ref.read(discourseServiceProvider).getTopic(topicId);
  } on RateLimitException catch (e) {
    // 特殊处理：延迟后自动重试
    await Future.delayed(Duration(seconds: e.retryAfterSeconds ?? 60));
    return await ref.read(discourseServiceProvider).getTopic(topicId);
  } on CfChallengeException catch (e) {
    // Cloudflare 验证：通知 UI 弹出验证对话框
    ref.read(cfChallengeProvider.notifier).showChallenge();
    rethrow;
  } catch (e) {
    // 其他异常：记录日志并重新抛出
    AppLogger.error('加载话题失败', error: e);
    rethrow;
  }
}
```

### 4. UI 层：展示错误信息

```dart
// lib/widgets/common/error_view.dart
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = _getErrorMessage(error);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: Text('重试')),
          ],
        ],
      ),
    );
  }

  String _getErrorMessage(Object error) {
    if (error is RateLimitException) return error.toString();
    if (error is ServerException) return error.toString();
    if (error is CfChallengeException) return error.toString();
    return S.current.error_unknown;
  }
}
```

---

## API Error Responses

### 标准 API 错误格式

Discourse API 返回的错误格式：

```json
{
  "errors": ["错误描述1", "错误描述2"],
  "error_type": "invalid_access"
}
```

### 错误解析

```dart
Exception _parseApiError(Map<String, dynamic> json) {
  final errors = json['errors'] as List<dynamic>?;
  final errorType = json['error_type'] as String?;
  
  if (errorType == 'invalid_access') {
    return Exception(S.current.error_permissionDenied);
  }
  
  if (errors != null && errors.isNotEmpty) {
    return Exception(errors.first.toString());
  }
  
  return Exception(S.current.error_unknown);
}
```

---

## Logging

### 使用统一日志入口

```dart
// lib/services/app_logger.dart
class AppLogger {
  /// 信息级别日志（控制台 + 文件）
  static void info(String message, {String? tag}) {
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'info',
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
    Catcher2.reportCheckedError(
      error ?? message,
      stackTrace ?? StackTrace.current,
      extraData: {'message': message, 'tag': tag},
    );
  }
}
```

### 日志使用示例

```dart
// 网络请求成功
AppLogger.info('用户登录成功', tag: 'Auth');

// 网络请求失败
try {
  await discourseService.login(username, password);
} catch (e, st) {
  AppLogger.error('登录失败', tag: 'Auth', error: e, stackTrace: st);
  rethrow;
}
```

---

## Common Mistakes

### ❌ 捕获所有异常但不处理

```dart
try {
  await fetchData();
} catch (e) {
  // bad: 吞掉异常，用户看不到任何提示
}
```

### ✅ 正确：记录日志并重新抛出或处理

```dart
try {
  await fetchData();
} catch (e) {
  AppLogger.error('获取数据失败', error: e);
  rethrow; // 或显示错误提示
}
```

---

### ❌ 使用泛型异常

```dart
throw Exception('操作失败'); // bad: 无法区分错误类型
```

### ✅ 正确：使用明确的异常类型

```dart
throw RateLimitException(60, '请求过于频繁，请 60 秒后重试');
```

---

### ❌ 在服务层直接显示 UI

```dart
class TopicService {
  Future<void> deleteTopic(int id) async {
    try {
      await _dio.delete('/t/$id');
    } catch (e) {
      // bad: 服务层不应直接操作 UI
      showDialog(context: context, builder: (_) => ErrorDialog());
    }
  }
}
```

### ✅ 正确：服务层抛出异常，UI 层处理

```dart
// Service
Future<void> deleteTopic(int id) async {
  try {
    await _dio.delete('/t/$id');
  } catch (e) {
    throw _handleDioError(e);
  }
}

// UI
onPressed: () async {
  try {
    await ref.read(topicProvider.notifier).deleteTopic(id);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}
```

---

### ❌ 异常消息使用硬编码

```dart
throw Exception('Rate limit exceeded'); // bad: 不支持国际化
```

### ✅ 正确：使用国际化字符串

```dart
throw RateLimitException(60, S.current.error_rateLimitedRetryLater);
```
