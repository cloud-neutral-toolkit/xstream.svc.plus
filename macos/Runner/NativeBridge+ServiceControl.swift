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
      _ = serviceName
      let running = isDirectXrayRunning()
      if !running {
        result(false)
        return
      }
      guard let currentNode = nodeName, !currentNode.isEmpty else {
        result(true)
        return
      }
      result(readActiveNodeName() == currentNode)

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
    guard let sourceConfig = configPath?.trimmingCharacters(in: .whitespacesAndNewlines),
          !sourceConfig.isEmpty else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing configPath", details: nil))
      return
    }
    guard FileManager.default.fileExists(atPath: sourceConfig) else {
      result(FlutterError(code: "CONFIG_MISSING", message: "source config not found", details: sourceConfig))
      return
    }

    let runtimeConfigPath = resolvedRuntimeConfigPath()
    let runtimeLogPath = resolvedRuntimeLogPath()
    guard let xrayExecutable = resolvedXrayExecutablePath() else {
      let details = "runtimeConfig=\(runtimeConfigPath), runtimeLog=\(runtimeLogPath), resourcePath=\(Bundle.main.resourcePath ?? "nil")"
      result(FlutterError(code: "PATH_RESOLVE_FAILED", message: "resolve runtime path failed", details: details))
      return
    }
    let requestedNodeName = (nodeName?.isEmpty == false) ? nodeName! : "default-node"
    logToFlutter("info", "startNodeService request node=\(requestedNodeName), sourceConfig=\(sourceConfig)")
    let runningBeforeStart = isDirectXrayRunning()
    if runningBeforeStart {
      let activeNode = readActiveNodeName()
      if activeNode == requestedNodeName {
        result("服务已在运行")
        return
      }
      _ = stopDirectXray()
      if isDirectXrayRunning() {
        result(FlutterError(code: "EXEC_FAILED", message: "xray stop existing process failed", details: nil))
        return
      }
    }
    if !FileManager.default.isExecutableFile(atPath: xrayExecutable) {
      result(FlutterError(code: "XRAY_MISSING", message: "xray not initialized", details: xrayExecutable))
      return
    }

    let escapedSourceConfig = shellEscaped(sourceConfig)
    let escapedRuntimeConfig = shellEscaped(runtimeConfigPath)
    let escapedRuntimeLog = shellEscaped(runtimeLogPath)
    let escapedXray = shellEscaped(xrayExecutable)
    logToFlutter("info", "starting xray executable=\(xrayExecutable), runtimeConfig=\(runtimeConfigPath), runtimeLog=\(runtimeLogPath)")

let prepareCommand = """
XRAY_CFG=\(escapedRuntimeConfig)
XRAY_LOG=\(escapedRuntimeLog)
SRC_CFG=\(escapedSourceConfig)
mkdir -p "$(dirname "$XRAY_CFG")"
mkdir -p "$(dirname "$XRAY_LOG")"
ln -sfn "$SRC_CFG" "$XRAY_CFG"
: > "$XRAY_LOG"
"""
    let (prepareOK, prepareOutput) = runCommandAndCapture(command: prepareCommand)
    if !prepareOK {
      result(FlutterError(code: "PREPARE_FAILED", message: "prepare config failed", details: prepareOutput))
      return
    }

    let startCommand = """
XRAY_BIN=\(escapedXray)
XRAY_CFG=\(escapedRuntimeConfig)
XRAY_LOG=\(escapedRuntimeLog)
nohup "$XRAY_BIN" run -c "$XRAY_CFG" >"$XRAY_LOG" 2>&1 &
sleep 1
"""
    let (startOK, startOutput) = runCommandAndCapture(command: startCommand)
    if !startOK {
      clearActiveNodeName()
      result(FlutterError(code: "EXEC_FAILED", message: "start xray failed", details: startOutput))
      return
    }

    if isDirectXrayRunning() {
      writeActiveNodeName(requestedNodeName)
      let suffix = requestedNodeName.isEmpty ? "" : " (\(requestedNodeName))"
      result("success: xray started\(suffix)")
      return
    }

    let (_, runtimeLogTail) = runCommandAndCapture(command: "tail -n 80 \(escapedRuntimeLog)")
    clearActiveNodeName()
    let details = runtimeLogTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? startOutput
      : runtimeLogTail
    result(FlutterError(code: "EXEC_FAILED", message: "xray not running after start", details: details))
  }

  private func stopNodeServiceWithDirectXray(result: @escaping FlutterResult) {
    if stopDirectXray() {
      logToFlutter("info", "stopNodeService success")
      clearActiveNodeName()
      result("success")
      return
    }
    logToFlutter("error", "stopNodeService failed: process still running")
    result("停止失败: 进程仍在运行")
  }

  private func isDirectXrayRunning() -> Bool {
    guard let xrayExecutable = resolvedXrayExecutablePath() else {
      return false
    }
    let runtimeConfigPath = resolvedRuntimeConfigPath()
    let escapedRuntimeConfig = shellEscaped(runtimeConfigPath)
    let escapedXray = shellEscaped(xrayExecutable)
    let checkCommand = """
XRAY_BIN=\(escapedXray)
XRAY_CFG=\(escapedRuntimeConfig)
pgrep -f "$XRAY_BIN run -c $XRAY_CFG" >/dev/null
"""
    let (ok, _) = runCommandAndCapture(command: checkCommand)
    return ok
  }

  private func stopDirectXray() -> Bool {
    guard let xrayExecutable = resolvedXrayExecutablePath() else {
      return false
    }
    let runtimeConfigPath = resolvedRuntimeConfigPath()
    let escapedRuntimeConfig = shellEscaped(runtimeConfigPath)
    let escapedXray = shellEscaped(xrayExecutable)
    let stopCommand = """
XRAY_BIN=\(escapedXray)
XRAY_CFG=\(escapedRuntimeConfig)
pkill -f "$XRAY_BIN run -c $XRAY_CFG" || true
sleep 1
"""
    _ = runCommandAndCapture(command: stopCommand)
    return !isDirectXrayRunning()
  }

  private func verifySocks5Proxy(result: @escaping FlutterResult) {
    guard isDirectXrayRunning() else {
      result("验证失败: xray 未运行")
      return
    }

    let endpoints = [
      "https://api.ipify.org",
      "https://ifconfig.me/ip",
      "http://api.ipify.org",
      "http://ifconfig.me/ip",
    ]
    var lastError = ""

    for endpoint in endpoints {
      let curlCommand = "/usr/bin/curl --silent --show-error --max-time 12 --socks5-hostname 127.0.0.1:1080 \(endpoint)"
      let (ok, output) = runCommandAndCapture(command: curlCommand)
      let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
      if ok && !normalized.isEmpty {
        result("success: socks5 可用，出口 IP=\(normalized)")
        return
      }
      if !normalized.isEmpty {
        lastError = normalized
      }
    }

    result("验证失败: \(lastError.isEmpty ? "socks5 请求无响应" : lastError)")
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

  private func resolvedAppSupportRoot() -> URL? {
    let fileManager = FileManager.default
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    let bundleId = Bundle.main.bundleIdentifier ?? "com.xstream"
    let root = appSupport.appendingPathComponent(bundleId, isDirectory: true)
    try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func resolvedRuntimeConfigPath() -> String {
    let configDir = resolvedRuntimeBaseDir().appendingPathComponent("configs", isDirectory: true)
    try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    return configDir.appendingPathComponent("config.json").path
  }

  private func resolvedRuntimeLogPath() -> String {
    let logsDir = resolvedRuntimeBaseDir().appendingPathComponent("logs", isDirectory: true)
    try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    return logsDir.appendingPathComponent("xray-runtime.log").path
  }

  private func resolvedXrayExecutablePath() -> String? {
    let fileManager = FileManager.default
    guard let bundledPath = resolvedBundledXrayPath() else {
      return nil
    }

    let binDir = resolvedExecutableStagingDir()
    let stagedPath = binDir.appendingPathComponent("xray").path

    if fileManager.isExecutableFile(atPath: stagedPath) {
      return stagedPath
    }

    if !fileManager.fileExists(atPath: stagedPath) {
      guard stageBundledXrayToAppSupport(sourcePath: bundledPath, targetPath: stagedPath, binDir: binDir) else {
        return fileManager.isExecutableFile(atPath: bundledPath) ? bundledPath : nil
      }
      return stagedPath
    }

    if ensureExecutable(path: stagedPath) {
      return stagedPath
    }

    guard stageBundledXrayToAppSupport(sourcePath: bundledPath, targetPath: stagedPath, binDir: binDir) else {
      return fileManager.isExecutableFile(atPath: bundledPath) ? bundledPath : nil
    }
    return stagedPath
  }

  private func shellEscaped(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
    return "'\(escaped)'"
  }

  private func normalizedArch() -> String {
    let process = Process()
    process.launchPath = "/usr/bin/uname"
    process.arguments = ["-m"]
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "arm64"
    } catch {
      return "arm64"
    }
  }

  private func resolvedStateDirectory() -> URL? {
    guard let root = resolvedAppSupportRoot() else { return nil }
    let stateDir = root.appendingPathComponent("state", isDirectory: true)
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    return stateDir
  }

  private func resolvedActiveNodeNamePath() -> URL? {
    guard let stateDir = resolvedStateDirectory() else { return nil }
    return stateDir.appendingPathComponent("active_node_name.txt")
  }

  private func writeActiveNodeName(_ nodeName: String) {
    guard let fileURL = resolvedActiveNodeNamePath() else { return }
    try? nodeName.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  private func readActiveNodeName() -> String? {
    guard let fileURL = resolvedActiveNodeNamePath(),
          let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return nil
    }
    let name = content.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
  }

  private func clearActiveNodeName() {
    guard let fileURL = resolvedActiveNodeNamePath() else { return }
    try? FileManager.default.removeItem(at: fileURL)
  }

  private func resolvedBundledXrayPath() -> String? {
    guard let resourcePath = Bundle.main.resourcePath else { return nil }
    let arch = normalizedArch()
    let candidates: [String] = (arch == "x86_64")
      ? [
        "\(resourcePath)/xray-x86_64",
        "\(resourcePath)/xray",
        "\(resourcePath)/xray/xray-x86_64",
        "\(resourcePath)/xray/xray",
        "\(resourcePath)/xray.x86_64",
        "\(resourcePath)/xray-arm64",
      ]
      : [
        "\(resourcePath)/xray",
        "\(resourcePath)/xray-arm64",
        "\(resourcePath)/xray/xray",
        "\(resourcePath)/xray/xray-arm64",
        "\(resourcePath)/xray-x86_64",
        "\(resourcePath)/xray.x86_64",
      ]
    return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
  }

  private func ensureExecutable(path: String) -> Bool {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path) else { return false }
    if fileManager.isExecutableFile(atPath: path) {
      return true
    }
    do {
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
      return fileManager.isExecutableFile(atPath: path)
    } catch {
      let chmod = Process()
      chmod.launchPath = "/bin/chmod"
      chmod.arguments = ["755", path]
      do {
        try chmod.run()
        chmod.waitUntilExit()
        if chmod.terminationStatus == 0, fileManager.isExecutableFile(atPath: path) {
          return true
        }
      } catch {
        // Fall through and log below.
      }
      logToFlutter("error", "set executable failed: \(path), error=\(error.localizedDescription)")
      return false
    }
  }

  private func stageBundledXrayToAppSupport(sourcePath: String, targetPath: String, binDir: URL) -> Bool {
    let fileManager = FileManager.default
    do {
      if fileManager.fileExists(atPath: targetPath) {
        try fileManager.removeItem(atPath: targetPath)
      }
      try fileManager.copyItem(atPath: sourcePath, toPath: targetPath)
      guard ensureExecutable(path: targetPath) else {
        return false
      }

      if let resourcePath = Bundle.main.resourcePath {
        for datName in ["geoip.dat", "geosite.dat"] {
          let sourceCandidates = [
            URL(fileURLWithPath: resourcePath).appendingPathComponent(datName),
            URL(fileURLWithPath: resourcePath)
              .appendingPathComponent("xray", isDirectory: true)
              .appendingPathComponent(datName),
          ]
          if let source = sourceCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            let destination = binDir.appendingPathComponent(datName)
            if fileManager.fileExists(atPath: destination.path) {
              try? fileManager.removeItem(at: destination)
            }
            try? fileManager.copyItem(at: source, to: destination)
          }
        }
      }

      return true
    } catch {
      logToFlutter("error", "stage bundled xray failed: \(error.localizedDescription)")
      return false
    }
  }

  private func resolvedExecutableStagingDir() -> URL {
    let fileManager = FileManager.default
    if let root = resolvedAppSupportRoot() {
      let dir = root.appendingPathComponent("bin", isDirectory: true)
      do {
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
      } catch {
        logToFlutter("warn", "app support bin unavailable, fallback to tmp: \(error.localizedDescription)")
      }
    }
    let fallback = fileManager.temporaryDirectory
      .appendingPathComponent("xstream-runtime", isDirectory: true)
      .appendingPathComponent("bin", isDirectory: true)
    try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
    return fallback
  }

  private func resolvedRuntimeBaseDir() -> URL {
    let fileManager = FileManager.default
    if let root = resolvedAppSupportRoot() {
      return root
    }
    let fallback = fileManager.temporaryDirectory
      .appendingPathComponent("xstream-runtime", isDirectory: true)
    try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
    return fallback
  }
}
