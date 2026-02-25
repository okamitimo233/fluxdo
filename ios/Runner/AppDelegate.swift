import Flutter
import UIKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 注册 iOS 后台任务 handler（必须在 didFinishLaunchingWithOptions 返回前调用）
    WorkmanagerPlugin.registerTask(withIdentifier: "com.fluxdo.notificationPoll")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
