// NativeBridge+XrayInit.swift

import Foundation
import FlutterMacOS

extension AppDelegate {
  func handlePerformAction(call: FlutterMethodCall, bundleId: String, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let action = args["action"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing action", details: nil))
      return
    }

    switch action {
    case "isXrayDownloading":
      result("0")
    case "resetXrayAndConfig":
      guard let password = args["password"] as? String else {
        result(FlutterError(code: "MISSING_PASSWORD", message: "缺少密码", details: nil))
        return
      }
      self.runResetXray(bundleId: bundleId, password: password, result: result)
    default:
      result(FlutterError(code: "UNKNOWN_ACTION", message: "Unsupported action", details: action))
    }
  }

  func runResetXray(bundleId: String, password _: String, result: @escaping FlutterResult) {
    guard let root = resolveAppSupportRoot(bundleId: bundleId) else {
      result("❌ 重置失败: 无法定位 Application Support 目录")
      return
    }

    // Let Dart side handle stopping Xray via FFI before calling this method if needed.

    do {
      let fm = FileManager.default
      if fm.fileExists(atPath: root.path) {
        try fm.removeItem(at: root)
      }
      result("✅ 已清除 Application Support 下 Xray 数据")
      logToFlutter("info", "重置完成: \(root.path)")
    } catch {
      result("❌ 重置失败: \(error.localizedDescription)")
      logToFlutter("error", "重置失败: \(error.localizedDescription)")
    }
  }

  private func resolveAppSupportRoot(bundleId: String) -> URL? {
    guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    let root = appSupport.appendingPathComponent(bundleId, isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

}
