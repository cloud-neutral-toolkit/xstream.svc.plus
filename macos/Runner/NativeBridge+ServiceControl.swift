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
    }
    // Always stop existing instance before a new launch.
    _ = stopDirectXray()
    if isDirectXrayRunning() {
      result(
        FlutterError(
          code: "EXEC_FAILED",
          message: "xray stop existing process failed",
          details: "process still running after terminate"
        )
      )
      return
    }
    if !FileManager.default.isExecutableFile(atPath: xrayExecutable) {
      result(FlutterError(code: "XRAY_MISSING", message: "xray not initialized", details: xrayExecutable))
      return
    }

    logToFlutter("info", "starting xray executable=\(xrayExecutable), runtimeConfig=\(runtimeConfigPath), runtimeLog=\(runtimeLogPath)")

    // Prepare directories using FileManager (no shell).
    let fm = FileManager.default
    let configDir = (runtimeConfigPath as NSString).deletingLastPathComponent
    let logDir = (runtimeLogPath as NSString).deletingLastPathComponent
    try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    fm.createFile(atPath: runtimeLogPath, contents: nil)

    do {
      let removedTunInbounds = try prepareDirectRuntimeConfig(
        sourcePath: sourceConfig,
        runtimeConfigPath: runtimeConfigPath
      )
      if removedTunInbounds > 0 {
        logToFlutter("info", "direct runtime config sanitized: removed \(removedTunInbounds) tun inbound(s)")
      }
    } catch {
      clearActiveNodeName()
      result(
        FlutterError(
          code: "PREPARE_FAILED",
          message: "prepare runtime config failed",
          details: error.localizedDescription
        )
      )
      return
    }

    // Launch xray via Foundation.Process (replaces nohup shell).
    let process = Process()
    process.executableURL = URL(fileURLWithPath: xrayExecutable)
    process.arguments = ["run", "-c", runtimeConfigPath]
    process.currentDirectoryURL = URL(fileURLWithPath: (xrayExecutable as NSString).deletingLastPathComponent)

    do {
      let logFileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: runtimeLogPath))
      logFileHandle.seekToEndOfFile()
      process.standardOutput = logFileHandle
      process.standardError = logFileHandle
    } catch {
      clearActiveNodeName()
      result(FlutterError(code: "LOG_SETUP_FAILED", message: "failed to open log file for writing", details: error.localizedDescription))
      return
    }

    do {
      try process.run()
    } catch {
      clearActiveNodeName()
      result(FlutterError(code: "EXEC_FAILED", message: "start xray failed", details: error.localizedDescription))
      return
    }

    xrayProcess = process

    if waitForDirectXrayReady(runtimeLogPath: runtimeLogPath, timeoutSeconds: 3.0) {
      writeActiveNodeName(requestedNodeName)
      let suffix = requestedNodeName.isEmpty ? "" : " (\(requestedNodeName))"
      result("success: xray started\(suffix)")
      return
    }

    // Startup verification failed — read log tail for diagnostics.
    let logTail = readLogTail(runtimeLogPath: runtimeLogPath, lines: 80)
    clearActiveNodeName()
    result(FlutterError(code: "EXEC_FAILED", message: "xray not running after start", details: logTail))
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
    guard let process = xrayProcess else {
      return false
    }
    return process.isRunning
  }

  private func stopDirectXray() -> Bool {
    guard let process = xrayProcess else {
      return true
    }
    if process.isRunning {
      process.terminate()
      // Give process time to exit gracefully.
      let deadline = Date().addingTimeInterval(2.0)
      while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
      }
      // Force kill if still running.
      if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
        Thread.sleep(forTimeInterval: 0.3)
      }
    }
    xrayProcess = nil
    return true
  }

  private func waitForDirectXrayReady(runtimeLogPath: String, timeoutSeconds: TimeInterval) -> Bool {
    let started = Date()
    while Date().timeIntervalSince(started) < timeoutSeconds {
      guard isDirectXrayRunning() else {
        // Process exited prematurely.
        return false
      }
      if hasXrayStartedMarker(runtimeLogPath: runtimeLogPath) {
        return true
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return isDirectXrayRunning() && hasXrayStartedMarker(runtimeLogPath: runtimeLogPath)
  }

  private func hasXrayStartedMarker(runtimeLogPath: String) -> Bool {
    guard let content = try? String(contentsOfFile: runtimeLogPath, encoding: .utf8) else {
      return false
    }
    let lines = content.components(separatedBy: .newlines)
    let tail = lines.suffix(120).joined(separator: "\n")
    let pattern = #"core: Xray .* started|Xray [0-9]+\.[0-9]+\.[0-9]+ started"#
    return tail.range(of: pattern, options: .regularExpression) != nil
  }

  private func readLogTail(runtimeLogPath: String, lines: Int) -> String {
    guard let content = try? String(contentsOfFile: runtimeLogPath, encoding: .utf8) else {
      return ""
    }
    let allLines = content.components(separatedBy: .newlines)
    return allLines.suffix(lines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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

  private func prepareDirectRuntimeConfig(
    sourcePath: String,
    runtimeConfigPath: String
  ) throws -> Int {
    let sourceData = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
    var removedTunInbounds = 0

    if var doc = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any],
       let inbounds = doc["inbounds"] as? [Any] {
      let filteredInbounds = inbounds.filter { inbound in
        guard let map = inbound as? [String: Any] else {
          return true
        }
        let protocolName = (map["protocol"] as? String)?.lowercased() ?? ""
        if protocolName == "tun" {
          removedTunInbounds += 1
          return false
        }
        return true
      }
      doc["inbounds"] = filteredInbounds
      let outputData = try JSONSerialization.data(
        withJSONObject: doc,
        options: [.prettyPrinted, .sortedKeys]
      )
      try outputData.write(
        to: URL(fileURLWithPath: runtimeConfigPath),
        options: [.atomic]
      )
      return removedTunInbounds
    }

    // Fallback for unexpected structure: preserve existing behavior by copying as-is.
    let fm = FileManager.default
    if sourcePath == runtimeConfigPath {
      return 0
    }
    if fm.fileExists(atPath: runtimeConfigPath) {
      try fm.removeItem(atPath: runtimeConfigPath)
    }
    try fm.copyItem(atPath: sourcePath, toPath: runtimeConfigPath)
    return 0
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
