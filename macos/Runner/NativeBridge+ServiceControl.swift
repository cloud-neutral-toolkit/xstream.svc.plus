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
      startNodeServiceWithDirectXray(
        configPath: configPath,
        nodeName: nodeName,
        result: result
      )

    case "stopNodeService":
      stopNodeServiceWithDirectXray(result: result)

    case "checkNodeStatus":
      // serviceName is optional now; keep it for future fallback compatibility
      _ = serviceName
      let running = isDirectXrayRunning()
      result(running)

    case "verifySocks5Proxy":
      verifySocks5Proxy(result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func runShellScript(command: String, returnsBool: Bool, result: @escaping FlutterResult) {
    let task = Process()
    task.launchPath = "/bin/zsh"
    task.arguments = ["-c", command]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      let isSuccess = (task.terminationStatus == 0)

      // ✅ 处理 checkNodeStatus
      if returnsBool {
        // 高版本: launchctl print
        if command.contains("launchctl print") {
          let isRunning = output.contains("state = running") || output.contains("PID =")
          result(isRunning)
          return
        }
        // 低版本: launchctl list | grep
        if command.contains("launchctl list") {
          let isListed = isSuccess && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          result(isListed)
          return
        }
        // 默认 fallback
        result(false)
        return
      }
      // ✅ 非 checkNodeStatus 情况
      if isSuccess {
        result("success")
        let safeCommand = maskSensitive(command)
        self.logToFlutter("info", "命令执行成功: \nCommand: \(safeCommand)\nOutput: \(output)")
      } else {
        if command.contains("bootstrap") && output.contains("Service is already loaded") {
          result("服务已在运行")
          let safeCommand = maskSensitive(command)
          self.logToFlutter("warn", "服务已在运行（重复启动）: \(safeCommand)")
        } else {
          result(FlutterError(code: "EXEC_FAILED", message: "Command failed", details: output))
          let safeCommand = maskSensitive(command)
          self.logToFlutter("error", "命令执行失败: \nCommand: \(safeCommand)\nOutput: \(output)")
        }
      }
    } catch {
      result(FlutterError(code: "EXEC_ERROR", message: "Process failed to run", details: error.localizedDescription))
      self.logToFlutter("error", "Process failed to run: \(error.localizedDescription)")
    }
  }

  private func maskSensitive(_ command: String) -> String {
    let pattern = #"echo\s+\"([^\"]+)\"\s*\|\s*sudo\s+-S"#
    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
      let range = NSRange(command.startIndex..., in: command)
      return regex.stringByReplacingMatches(in: command, options: [], range: range, withTemplate: "echo \"****\" | sudo -S")
    }
    return command
  }

  private func startNodeServiceWithDirectXray(
    configPath: String?,
    nodeName: String?,
    result: @escaping FlutterResult
  ) {
    if isDirectXrayRunning() {
      result("服务已在运行")
      return
    }

    guard let sourceConfig = configPath?.trimmingCharacters(in: .whitespacesAndNewlines),
          !sourceConfig.isEmpty else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing configPath", details: nil))
      return
    }

    let prepareCommand = """
mkdir -p /opt/homebrew/etc/xray
cp -f "\(sourceConfig)" /opt/homebrew/etc/xray/config.json
"""
    let (prepareOK, prepareOutput) = runCommandAndCapture(command: prepareCommand)
    if !prepareOK {
      result(FlutterError(code: "PREPARE_FAILED", message: "prepare config failed", details: prepareOutput))
      return
    }

    let startCommand = """
nohup /opt/homebrew/bin/xray run -c /opt/homebrew/etc/xray/config.json >/tmp/xstream-xray-runtime.log 2>&1 &
sleep 1
"""
    let (startOK, startOutput) = runCommandAndCapture(command: startCommand)
    if !startOK {
      result(FlutterError(code: "EXEC_FAILED", message: "start xray failed", details: startOutput))
      return
    }

    if isDirectXrayRunning() {
      let suffix = (nodeName == nil || nodeName!.isEmpty) ? "" : " (\(nodeName!))"
      result("success: xray started\(suffix)")
      return
    }

    result(FlutterError(code: "EXEC_FAILED", message: "xray not running after start", details: startOutput))
  }

  private func stopNodeServiceWithDirectXray(result: @escaping FlutterResult) {
    let stopCommand = """
pkill -f "/opt/homebrew/bin/xray run -c /opt/homebrew/etc/xray/config.json" || true
sleep 1
"""
    _ = runCommandAndCapture(command: stopCommand)
    result(isDirectXrayRunning() ? "停止失败: 进程仍在运行" : "success")
  }

  private func isDirectXrayRunning() -> Bool {
    let checkCommand = "pgrep -f \"/opt/homebrew/bin/xray run -c /opt/homebrew/etc/xray/config.json\" >/dev/null"
    let (ok, _) = runCommandAndCapture(command: checkCommand)
    return ok
  }

  private func verifySocks5Proxy(result: @escaping FlutterResult) {
    guard isDirectXrayRunning() else {
      result("验证失败: xray 未运行")
      return
    }

    let curlCommand = "/usr/bin/curl --silent --show-error --max-time 12 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org"
    let (ok, output) = runCommandAndCapture(command: curlCommand)
    let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if ok && !normalized.isEmpty {
      result("success: socks5 可用，出口 IP=\(normalized)")
      return
    }
    result("验证失败: \(normalized.isEmpty ? "socks5 请求无响应" : normalized)")
  }

  private func runCommandAndCapture(command: String) -> (Bool, String) {
    let task = Process()
    task.launchPath = "/bin/zsh"
    task.arguments = ["-c", command]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      return (task.terminationStatus == 0, output)
    } catch {
      return (false, error.localizedDescription)
    }
  }
}
