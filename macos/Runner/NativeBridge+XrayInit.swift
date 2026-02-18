// NativeBridge+XrayInit.swift

import Foundation
import FlutterMacOS

private let artifactBaseURL = "https://artifact.svc.plus"

extension AppDelegate {
  func handlePerformAction(call: FlutterMethodCall, bundleId: String, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let action = args["action"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing action", details: nil))
      return
    }

    switch action {
    case "initXray":
      self.runInitXray(bundleId: bundleId, result: result)
    case "updateXrayCore":
      self.runUpdateXrayCore(result: result)
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

  func runInitXray(bundleId: String, result: @escaping FlutterResult) {
    guard let resourcePath = Bundle.main.resourcePath else {
      result("❌ 无法获取 Resources 路径")
      return
    }

    guard let root = resolveAppSupportRoot(bundleId: bundleId) else {
      result("❌ 无法定位 Application Support 目录")
      return
    }

    do {
      let fm = FileManager.default
      let binDir = root.appendingPathComponent("bin", isDirectory: true)
      try fm.createDirectory(at: binDir, withIntermediateDirectories: true)

      let archProcess = Process()
      archProcess.launchPath = "/usr/bin/uname"
      archProcess.arguments = ["-m"]
      let archPipe = Pipe()
      archProcess.standardOutput = archPipe
      try archProcess.run()
      archProcess.waitUntilExit()
      let archData = archPipe.fileHandleForReading.readDataToEndOfFile()
      let arch = String(data: archData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "arm64"
      let sourceCandidates: [String]
      if arch == "x86_64" {
        sourceCandidates = [
          "\(resourcePath)/xray-x86_64",
          "\(resourcePath)/xray.x86_64",
          "\(resourcePath)/xray",
        ]
      } else {
        sourceCandidates = [
          "\(resourcePath)/xray",
          "\(resourcePath)/xray-arm64",
        ]
      }

      guard let source = sourceCandidates.first(where: { fm.fileExists(atPath: $0) }) else {
        result("❌ Resources 中未找到 xray 可执行文件")
        return
      }

      let target = binDir.appendingPathComponent("xray")
      if fm.fileExists(atPath: target.path) {
        try fm.removeItem(at: target)
      }
      try fm.copyItem(atPath: source, toPath: target.path)
      try copyOptionalResource(
        fileName: "geoip.dat",
        resourcePath: resourcePath,
        destinationDir: binDir)
      try copyOptionalResource(
        fileName: "geosite.dat",
        resourcePath: resourcePath,
        destinationDir: binDir)

      let chmod = Process()
      chmod.launchPath = "/bin/chmod"
      chmod.arguments = ["755", target.path]
      try chmod.run()
      chmod.waitUntilExit()

      if chmod.terminationStatus != 0 {
        result("❌ xray 权限设置失败")
        return
      }

      result("✅ Xray 初始化完成: \(target.path)")
      logToFlutter("info", "Xray 初始化完成: \(target.path)")
    } catch {
      result("❌ Xray 初始化失败: \(error.localizedDescription)")
      logToFlutter("error", "Xray 初始化失败: \(error.localizedDescription)")
    }
  }

  func runUpdateXrayCore(result: @escaping FlutterResult) {
    let archProcess = Process()
    archProcess.launchPath = "/usr/bin/uname"
    archProcess.arguments = ["-m"]
    let archPipe = Pipe()
    archProcess.standardOutput = archPipe
    do {
      try archProcess.run()
    } catch {
      result("❌ 获取架构失败")
      return
    }
    archProcess.waitUntilExit()
    let archData = archPipe.fileHandleForReading.readDataToEndOfFile()
    let arch = String(data: archData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let urlString: String
    if arch == "arm64" {
      urlString = "\(artifactBaseURL)/xray-core/v25.3.6/Xray-macos-arm64-v8a.zip"
    } else {
      urlString = "\(artifactBaseURL)/xray-core/v25.3.6/Xray-macos-64.zip"
    }

    guard let url = URL(string: urlString) else {
      result("❌ 无效的下载地址")
      return
    }

    DispatchQueue.global(qos: .background).async {
      let task = URLSession.shared.downloadTask(with: url) { localURL, _, error in
        guard let localURL = localURL, error == nil else {
          self.logToFlutter("error", "下载失败: \(error?.localizedDescription ?? "unknown")")
          return
        }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.launchPath = "/usr/bin/unzip"
        unzip.arguments = ["-o", localURL.path, "-d", tempDir.path]
        try? unzip.run()
        unzip.waitUntilExit()

        var xrayPath = tempDir.appendingPathComponent("xray").path
        if !fm.fileExists(atPath: xrayPath) {
          if let first = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil).first {
            let candidate = first.appendingPathComponent("xray")
            if fm.fileExists(atPath: candidate.path) {
              xrayPath = candidate.path
            }
          }
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "com.xstream"
        if let root = self.resolveAppSupportRoot(bundleId: bundleId) {
          do {
            let binDir = root.appendingPathComponent("bin", isDirectory: true)
            try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
            let target = binDir.appendingPathComponent("xray")
            if fm.fileExists(atPath: target.path) {
              try fm.removeItem(at: target)
            }
            try fm.copyItem(atPath: xrayPath, toPath: target.path)
            try self.copyOptionalResource(
              fileName: "geoip.dat",
              resourcePath: Bundle.main.resourcePath ?? "",
              destinationDir: binDir)
            try self.copyOptionalResource(
              fileName: "geosite.dat",
              resourcePath: Bundle.main.resourcePath ?? "",
              destinationDir: binDir)
            let chmod = Process()
            chmod.launchPath = "/bin/chmod"
            chmod.arguments = ["755", target.path]
            try chmod.run()
            chmod.waitUntilExit()
            self.logToFlutter("info", "Xray 更新完成: \(target.path)")
          } catch {
            self.logToFlutter("error", "Xray 更新失败: \(error.localizedDescription)")
          }
        } else {
          self.logToFlutter("error", "Xray 更新失败: app support path unavailable")
        }

        try? fm.removeItem(at: tempDir)
      }
      task.resume()
    }

    result("info:download started")
  }

  func runResetXray(bundleId: String, password _: String, result: @escaping FlutterResult) {
    guard let root = resolveAppSupportRoot(bundleId: bundleId) else {
      result("❌ 重置失败: 无法定位 Application Support 目录")
      return
    }

    let runtimeConfig = root.appendingPathComponent("configs/config.json").path
    let xrayBin = root.appendingPathComponent("bin/xray").path
    let stop = Process()
    stop.launchPath = "/bin/zsh"
    stop.arguments = ["-c", "pkill -f \"\(xrayBin) run -c \(runtimeConfig)\" || true"]
    try? stop.run()
    stop.waitUntilExit()

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

  private func copyOptionalResource(
    fileName: String,
    resourcePath: String,
    destinationDir: URL
  ) throws {
    guard !resourcePath.isEmpty else { return }
    let fm = FileManager.default
    let source = URL(fileURLWithPath: resourcePath)
      .appendingPathComponent("xray", isDirectory: true)
      .appendingPathComponent(fileName)
    guard fm.fileExists(atPath: source.path) else { return }
    let destination = destinationDir.appendingPathComponent(fileName)
    if fm.fileExists(atPath: destination.path) {
      try fm.removeItem(at: destination)
    }
    try fm.copyItem(at: source, to: destination)
  }
}
