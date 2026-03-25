import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 注册 cookie 同步 channel，用于将 cookie 写入 HTTPCookieStorage.shared
    // WKWebView 的 sharedCookiesEnabled 在创建时从 HTTPCookieStorage.shared 读取 cookie
    let channel = FlutterMethodChannel(
      name: "com.fluxdo/cookie_storage",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setCookies":
        guard let args = call.arguments as? [[String: Any?]] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Expected list of cookie maps", details: nil))
          return
        }
        self.setCookiesToSharedStorage(args)
        result(true)
      case "clearCookies":
        let url = (call.arguments as? String) ?? ""
        self.clearCookiesFromSharedStorage(url: url)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 注册代理 CA 证书 channel（原生层 SSL challenge 拦截）
    let proxyCertChannel = FlutterMethodChannel(
      name: "com.fluxdo/proxy_cert",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    proxyCertChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setCaCertPem":
        guard let pem = call.arguments as? String else {
          result(false)
          return
        }
        let trusted = DohProxyCertHandler.shared.setCaCertPem(pem)
        result(trusted)
      case "isCaTrusted":
        result(DohProxyCertHandler.shared.isCaTrusted())
      case "clear":
        DohProxyCertHandler.shared.clearCaCert()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  /// 将 cookie 写入 HTTPCookieStorage.shared
  private func setCookiesToSharedStorage(_ cookieMaps: [[String: Any?]]) {
    let storage = HTTPCookieStorage.shared
    for map in cookieMaps {
      guard let name = map["name"] as? String,
            let value = map["value"] as? String,
            let urlString = map["url"] as? String else {
        continue
      }
      var properties: [HTTPCookiePropertyKey: Any] = [
        .originURL: urlString,
        .name: name,
        .value: value,
        .path: (map["path"] as? String) ?? "/",
      ]
      if let domain = map["domain"] as? String {
        properties[.domain] = domain
      } else if let host = URL(string: urlString)?.host {
        properties[.domain] = host
      }
      if let expiresMs = map["expiresDate"] as? Int, expiresMs > 0 {
        properties[.expires] = Date(timeIntervalSince1970: TimeInterval(Double(expiresMs) / 1000))
      }
      if let isSecure = map["isSecure"] as? Bool, isSecure {
        properties[.secure] = "TRUE"
      }
      if let isHttpOnly = map["isHttpOnly"] as? Bool, isHttpOnly {
        properties[.init("HttpOnly")] = "YES"
      }
      if let cookie = HTTPCookie(properties: properties) {
        storage.setCookie(cookie)
      }
    }
  }

  /// 清除 HTTPCookieStorage.shared 中指定 URL 的 cookie
  private func clearCookiesFromSharedStorage(url: String) {
    let storage = HTTPCookieStorage.shared
    guard let urlHost = URL(string: url)?.host else { return }
    if let cookies = storage.cookies {
      for cookie in cookies {
        if urlHost.hasSuffix(cookie.domain) || ".\(urlHost)".hasSuffix(cookie.domain) {
          storage.deleteCookie(cookie)
        }
      }
    }
  }
}
