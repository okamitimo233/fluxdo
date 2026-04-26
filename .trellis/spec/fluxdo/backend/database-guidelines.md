# Database Guidelines

> 数据持久化和缓存策略。

---

## Overview

本项目使用以下数据持久化方案：

- **SharedPreferences**：简单键值对数据（用户设置、小型缓存）
- **ResilientSecureStorage**：敏感数据（认证令牌、密码）
- **文件存储**：大型数据（日志、缓存文件）
- **内存缓存**：临时数据（Provider 状态、运行时缓存）

**注意**：本项目为前端应用，不使用传统数据库（如 SQLite），所有数据通过上述方案管理。

---

## Storage Solutions

### 1. SharedPreferences - 简单数据存储

**用途**：
- 用户设置（主题、语言、通知偏好）
- 小型缓存（用户信息摘要、书签列表）
- 标志位（首次启动、功能开关）

**示例**：

```dart
// lib/providers/core_providers.dart
class CurrentUserNotifier extends AsyncNotifier<User?> {
  static const String _cacheKey = 'current_user_cache';
  static const String _cacheUserKey = 'current_user_cache_username';

  Future<User?> _loadUserWithCache(DiscourseService service) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 读取缓存
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      final json = jsonDecode(cached) as Map<String, dynamic>;
      return User.fromCacheJson(json);
    }

    // 从网络获取并缓存
    final user = await service.getCurrentUser();
    if (user != null) {
      _saveCache(prefs, user);
    }
    return user;
  }

  void _saveCache(SharedPreferences prefs, User user) {
    prefs.setString(_cacheKey, jsonEncode(user.toCacheJson()));
    prefs.setString(_cacheUserKey, user.username);
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheUserKey);
  }
}
```

---

### 2. ResilientSecureStorage - 敏感数据存储

**用途**：
- 认证令牌（`_t` token）
- 用户凭证（用户名、密码）
- OAuth 密钥

**示例**：

```dart
// lib/services/storage/resilient_secure_storage.dart
class ResilientSecureStorage {
  final FlutterSecureStorage _storage;

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      // 处理 Android/iOS 存储失败
      await _handleStorageError(e);
      await _storage.write(key: key, value: value);
    }
  }

  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }
}

// lib/services/discourse/_auth.dart
class _AuthMixin on _DiscourseServiceBase {
  static const String _tokenKey = 'linux_do_token';
  static const String _usernameKey = 'linux_do_username';

  Future<void> _saveCredentials(String token, String username) async {
    await _storage.write(_tokenKey, token);
    await _storage.write(_usernameKey, username);
    _tToken = token;
    _username = username;
  }

  Future<void> _loadStoredCredentials() async {
    _tToken = await _storage.read(_tokenKey);
    _username = await _storage.read(_usernameKey);
    _credentialsLoaded = true;
  }
}
```

---

### 3. 文件存储 - 大型数据

**用途**：
- 日志文件（`LogWriter`）
- 缓存文件（图片、附件）
- 数据备份（用户数据导出）

**示例**：

```dart
// lib/services/log/log_writer.dart
class LogWriter {
  static final LogWriter instance = LogWriter._();
  File? _logFile;

  Future<void> write(Map<String, dynamic> log) async {
    final file = await _getLogFile();
    final content = jsonEncode(log) + '\n';
    await file.writeAsString(content, mode: FileMode.append);
  }

  Future<File> _getLogFile() async {
    if (_logFile != null) return _logFile!;
    
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/app_logs.jsonl');
    return _logFile!;
  }
}
```

---

### 4. 内存缓存 - Provider 状态

**用途**：
- 运行时状态（当前用户、话题列表）
- 临时缓存（已加载的数据、URL 映射）

**示例**：

```dart
// lib/services/discourse/discourse_service.dart
class DiscourseService extends _DiscourseServiceBase {
  // 用户摘要缓存（内存 + 时间戳）
  UserSummary? _cachedUserSummary;
  String? _cachedUserSummaryUsername;
  DateTime? _userSummaryCacheTime;
  static const _summaryCacheDuration = Duration(minutes: 5);

  Future<UserSummary> getUserSummary(String username) async {
    // 检查缓存是否有效
    if (_cachedUserSummary != null &&
        _cachedUserSummaryUsername == username &&
        _userSummaryCacheTime != null &&
        DateTime.now().difference(_userSummaryCacheTime!) < _summaryCacheDuration) {
      return _cachedUserSummary!;
    }

    // 从网络获取
    final summary = await _fetchUserSummary(username);
    
    // 更新缓存
    _cachedUserSummary = summary;
    _cachedUserSummaryUsername = username;
    _userSummaryCacheTime = DateTime.now();
    
    return summary;
  }

  // URL 缓存（上传图片后的 URL 映射）
  final Map<String, ResolvedUploadUrl> _urlCache = {};

  Future<ResolvedUploadUrl> resolveUploadUrl(String shortUrl) async {
    if (_urlCache.containsKey(shortUrl)) {
      return _urlCache[shortUrl]!;
    }
    final resolved = await _resolveUrl(shortUrl);
    _urlCache[shortUrl] = resolved;
    return resolved;
  }
}
```

---

## Cache Strategy

### 缓存层级

```
┌─────────────────────────────────────┐
│  Provider State (内存)              │  ← 生命周期随 Provider
│  - 当前用户、话题列表                │
└─────────────────────────────────────┘
                ↓
┌─────────────────────────────────────┐
│  Memory Cache (Service 内部)        │  ← 生命周期随 Service 实例
│  - 用户摘要、URL 映射                │
└─────────────────────────────────────┘
                ↓
┌─────────────────────────────────────┐
│  SharedPreferences (持久化)         │  ← 跨会话保留
│  - 用户信息、设置项                  │
└─────────────────────────────────────┘
                ↓
┌─────────────────────────────────────┐
│  SecureStorage (持久化 + 加密)      │  ← 敏感数据
│  - 认证令牌、密码                    │
└─────────────────────────────────────┘
```

---

### 缓存失效策略

**时间失效**：

```dart
// 用户摘要缓存 5 分钟后失效
if (_userSummaryCacheTime != null &&
    DateTime.now().difference(_userSummaryCacheTime!) > _summaryCacheDuration) {
  _cachedUserSummary = null; // 清除缓存
}
```

**事件失效**：

```dart
// 用户退出登录时清除所有缓存
Future<void> logout() async {
  await _storage.delete(_tokenKey);
  await _storage.delete(_usernameKey);
  
  // 清除内存缓存
  _cachedUserSummary = null;
  _cachedUserSummaryUsername = null;
  _urlCache.clear();
  
  // 清除 SharedPreferences 缓存
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('current_user_cache');
}
```

**主动刷新**：

```dart
// Provider 提供刷新方法
Future<void> refreshSilently({bool force = false}) async {
  if (!force && _lastRefreshTime != null &&
      DateTime.now().difference(_lastRefreshTime!) < _refreshCooldown) {
    return; // 冷却时间内跳过
  }
  
  final user = await _loadUser(service);
  _lastRefreshTime = DateTime.now();
  state = AsyncValue.data(user);
}
```

---

## Data Models

### 模型类设计

**使用工厂方法支持多种数据源**：

```dart
// lib/models/user.dart
class User {
  final String username;
  final String? name;
  final int? unreadNotifications;

  User({
    required this.username,
    this.name,
    this.unreadNotifications,
  });

  /// 从 API 响应解析
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      username: json['username'] as String,
      name: json['name'] as String?,
      unreadNotifications: json['unread_notifications'] as int?,
    );
  }

  /// 从缓存解析（可能缺少部分字段）
  factory User.fromCacheJson(Map<String, dynamic> json) {
    return User(
      username: json['username'] as String,
      name: json['name'] as String?,
      unreadNotifications: json['unread_notifications'] as int?,
    );
  }

  /// 转换为缓存格式
  Map<String, dynamic> toCacheJson() {
    return {
      'username': username,
      'name': name,
      'unread_notifications': unreadNotifications,
    };
  }

  /// 不可变更新
  User copyWith({
    String? username,
    String? name,
    int? unreadNotifications,
  }) {
    return User(
      username: username ?? this.username,
      name: name ?? this.name,
      unreadNotifications: unreadNotifications ?? this.unreadNotifications,
    );
  }
}
```

---

## Common Mistakes

### ❌ 在 SharedPreferences 中存储敏感数据

```dart
// bad: 明文存储密码
prefs.setString('password', password);
```

### ✅ 正确：使用 SecureStorage

```dart
await _storage.write('password', password);
```

---

### ❌ 缓存永不过期

```dart
// bad: 缓存没有失效机制
final cached = prefs.getString('user_data');
if (cached != null) return cached; // 永远使用缓存
```

### ✅ 正确：添加时间戳验证

```dart
final cachedTime = prefs.getInt('user_data_timestamp');
if (cachedTime != null && 
    DateTime.now().millisecondsSinceEpoch - cachedTime < cacheDuration) {
  return prefs.getString('user_data');
}
```

---

### ❌ 模型类可变

```dart
// bad: 可变字段
class User {
  String username;
  int likeCount;
  
  User({required this.username, this.likeCount});
}

// 在外部直接修改
user.likeCount++;
```

### ✅ 正确：不可变模型 + copyWith

```dart
class User {
  final String username;
  final int likeCount;

  const User({required this.username, required this.likeCount});

  User copyWith({String? username, int? likeCount}) {
    return User(
      username: username ?? this.username,
      likeCount: likeCount ?? this.likeCount,
    );
  }
}

// 使用 copyWith 创建新实例
user = user.copyWith(likeCount: user.likeCount + 1);
```

---

### ❌ 在模型类中直接调用 SharedPreferences

```dart
// bad: 模型类依赖具体存储实现
class User {
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('username', username);
  }
}
```

### ✅ 正确：存储逻辑放在 Service 或 Provider

```dart
// Service 或 Provider 负责存储
class UserService {
  Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('username', user.username);
  }
}
```
