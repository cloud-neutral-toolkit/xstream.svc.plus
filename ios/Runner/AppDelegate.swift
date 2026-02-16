import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let api = DarwinHostApiImpl(binaryMessenger: controller.binaryMessenger)
      DarwinHostApiSetup.setUp(binaryMessenger: controller.binaryMessenger, api: api)
    }

    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.xstream/native", binaryMessenger: controller.binaryMessenger)
      let bundleId = Bundle.main.bundleIdentifier ?? "com.xstream"
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "writeConfigFiles":
          self.writeConfigFiles(call: call, result: result)
        case "startNodeService", "stopNodeService", "checkNodeStatus":
          self.handleServiceControl(call: call, result: result)
        case "performAction":
          self.handlePerformAction(call: call, bundleId: bundleId, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
