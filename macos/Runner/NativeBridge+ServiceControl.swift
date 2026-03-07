import Foundation
import FlutterMacOS

extension AppDelegate {
  func handleServiceControl(call: FlutterMethodCall, bundleId: String, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let serviceNameArg = args["serviceName"] as? String
    let configPath = args["configPath"] as? String
    let nodeName = (args["nodeName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let serviceName = serviceNameArg?.replacingOccurrences(of: ".plist", with: "")

    switch call.method {
    case "startNodeService":
      // Now handled via FFI in Dart directly. Supported here as a no-op just in case.
      result("success: handled by FFI")

    case "stopNodeService":
      // Now handled via FFI in Dart directly. Supported here as a no-op just in case.
      result("success")

    case "checkNodeStatus":
      // Now handled via FFI in Dart directly.
      result(false)

    case "verifySocks5Proxy":
      // Consider implementing verifiable socks checking centrally via Dart or handle differently.
      result("验证失败: 不再通过 Swift 原生支持验证")

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
