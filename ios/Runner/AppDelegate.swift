import Flutter
import UIKit
import WebKit
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.flutter_rss_reader/cookies",
                                       binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getCookies":
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let url = URL(string: urlString) else {
          result(nil)
          return
        }

        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        if cookies.isEmpty {
          result(nil)
          return
        }

        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        result(header)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
