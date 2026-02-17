// AppDelegate.swift
import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  enum ProxyMode: String {
    case tun = "tun"
    case proxyOnly = "proxyOnly"
  }

  struct MenuState {
    var connected: Bool = false
    var nodeName: String = "-"
    var proxyMode: ProxyMode = .tun
    var launchAtLogin: Bool = false
  }

  private var statusItem: NSStatusItem?
  private var nativeChannel: FlutterMethodChannel?
  private var menuState = MenuState()

  private var statusLineItem = NSMenuItem(title: "Status: Disconnected", action: nil, keyEquivalent: "")
  private var nodeLineItem = NSMenuItem(title: "Node: -", action: nil, keyEquivalent: "")
  private var startStopItem = NSMenuItem(title: "Start Acceleration", action: #selector(toggleAcceleration), keyEquivalent: "")
  private var reconnectItem = NSMenuItem(title: "Reconnect", action: #selector(reconnectAcceleration), keyEquivalent: "")
  private var tunModeItem = NSMenuItem(title: "Tun Mode", action: #selector(selectTunMode), keyEquivalent: "")
  private var proxyOnlyModeItem = NSMenuItem(title: "Proxy Only", action: #selector(selectProxyOnlyMode), keyEquivalent: "")
  private var launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let window = mainFlutterWindow,
       let controller = window.contentViewController as? FlutterViewController {

      let channel = FlutterMethodChannel(name: "com.xstream/native", binaryMessenger: controller.engine.binaryMessenger)
      nativeChannel = channel

      let bundleId = Bundle.main.bundleIdentifier ?? "com.xstream"

      channel.setMethodCallHandler { [self] call, result in
        switch call.method {
        case "writeConfigFiles":
          self.writeConfigFiles(call: call, result: result)

        case "startNodeService", "stopNodeService", "checkNodeStatus", "verifySocks5Proxy":
          self.handleServiceControl(call: call, bundleId: bundleId, result: result)
        case "setSystemProxy":
          self.handleSystemProxy(call: call, result: result)

        case "performAction":
          self.handlePerformAction(call: call, bundleId: bundleId, result: result)
        case "updateMenuState":
          self.handleUpdateMenuState(call: call, result: result)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    menuState.launchAtLogin = isLaunchAtLoginEnabled()

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem?.button {
      button.image = NSImage(named: "StatusIcon") ?? NSApp.applicationIconImage
      button.image?.isTemplate = true
    }

    statusItem?.menu = buildStatusMenu()
    refreshMenuUI()

    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @objc func showMainWindow() {
    if let window = mainFlutterWindow {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  private func buildStatusMenu() -> NSMenu {
    let menu = NSMenu()

    statusLineItem.isEnabled = false
    nodeLineItem.isEnabled = false
    menu.addItem(statusLineItem)
    menu.addItem(nodeLineItem)
    menu.addItem(NSMenuItem.separator())

    startStopItem.target = self
    reconnectItem.target = self
    menu.addItem(startStopItem)
    menu.addItem(reconnectItem)
    menu.addItem(NSMenuItem.separator())

    let proxyModeMenu = NSMenu(title: "Proxy Mode")
    tunModeItem.target = self
    proxyOnlyModeItem.target = self
    proxyModeMenu.addItem(tunModeItem)
    proxyModeMenu.addItem(proxyOnlyModeItem)
    let proxyModeRootItem = NSMenuItem(title: "Proxy Mode", action: nil, keyEquivalent: "")
    proxyModeRootItem.submenu = proxyModeMenu
    menu.addItem(proxyModeRootItem)
    menu.addItem(NSMenuItem.separator())

    let showWindowItem = NSMenuItem(title: "Show Main Window", action: #selector(showMainWindowAndNotify), keyEquivalent: "")
    showWindowItem.target = self
    menu.addItem(showWindowItem)

    let openLogsItem = NSMenuItem(title: "Open Logs", action: #selector(openLogs), keyEquivalent: "")
    openLogsItem.target = self
    menu.addItem(openLogsItem)

    let editRulesItem = NSMenuItem(title: "Edit Rules", action: #selector(editRules), keyEquivalent: "")
    editRulesItem.target = self
    menu.addItem(editRulesItem)
    menu.addItem(NSMenuItem.separator())

    launchAtLoginItem.target = self
    menu.addItem(launchAtLoginItem)
    menu.addItem(NSMenuItem.separator())

    let quitStopItem = NSMenuItem(title: "Quit & Stop Acceleration", action: #selector(quitAndStopAcceleration), keyEquivalent: "")
    quitStopItem.target = self
    menu.addItem(quitStopItem)

    let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quitItem)

    return menu
  }

  private func refreshMenuUI() {
    statusLineItem.title = "Status: \(menuState.connected ? "Connected" : "Disconnected")"
    nodeLineItem.title = "Node: \(menuState.nodeName)"
    startStopItem.title = menuState.connected ? "Stop Acceleration" : "Start Acceleration"
    reconnectItem.isEnabled = menuState.nodeName != "-" && !menuState.nodeName.isEmpty
    tunModeItem.state = menuState.proxyMode == .tun ? .on : .off
    proxyOnlyModeItem.state = menuState.proxyMode == .proxyOnly ? .on : .off
    launchAtLoginItem.state = menuState.launchAtLogin ? .on : .off
  }

  @objc private func showMainWindowAndNotify() {
    showMainWindow()
    notifyFlutterMenuAction(action: "showMainWindow")
  }

  @objc private func openLogs() {
    if let logsDir = resolveLogsDirectory() {
      NSWorkspace.shared.open(logsDir)
    }
    showMainWindow()
    notifyFlutterMenuAction(action: "openLogs")
  }

  @objc private func editRules() {
    if let rulesFile = resolveRulesFile() {
      NSWorkspace.shared.open(rulesFile)
    }
    showMainWindow()
    notifyFlutterMenuAction(action: "editRules")
  }

  @objc private func selectTunMode() {
    menuState.proxyMode = .tun
    refreshMenuUI()
    notifyFlutterMenuAction(action: "setProxyMode", payload: ["mode": "VPN"])
  }

  @objc private func selectProxyOnlyMode() {
    menuState.proxyMode = .proxyOnly
    refreshMenuUI()
    notifyFlutterMenuAction(action: "setProxyMode", payload: ["mode": "仅代理"])
  }

  @objc private func toggleLaunchAtLogin() {
    let target = !menuState.launchAtLogin
    if setLaunchAtLoginEnabled(target) {
      menuState.launchAtLogin = target
      refreshMenuUI()
    }
  }

  @objc private func toggleAcceleration() {
    if menuState.connected {
      stopAcceleration()
    } else {
      startAcceleration()
    }
  }

  @objc private func reconnectAcceleration() {
    guard let node = resolveTargetNodeName() else { return }
    let stopSuccess = stopServiceForNode(node)
    if !stopSuccess {
      return
    }
    _ = startServiceForNode(node)
  }

  @objc private func quitAndStopAcceleration() {
    if let node = resolveTargetNodeName() {
      _ = stopServiceForNode(node)
    }
    NSApp.terminate(nil)
  }

  private func startAcceleration() {
    guard let node = resolveTargetNodeName() else { return }
    _ = startServiceForNode(node)
  }

  private func stopAcceleration() {
    guard let node = resolveTargetNodeName() else { return }
    _ = stopServiceForNode(node)
  }

  @discardableResult
  private func startServiceForNode(_ nodeName: String) -> Bool {
    guard let serviceName = serviceNameForNode(nodeName) else { return false }
    let servicePath = "/Users/\(NSUserName())/Library/LaunchAgents/\(serviceName)"
    let uid = getuid()
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let useModernLaunchctl = os.majorVersion >= 11 || (os.majorVersion == 10 && os.minorVersion >= 15)
    let command = useModernLaunchctl
      ? "launchctl bootstrap gui/\(uid) \"\(servicePath)\""
      : "launchctl load \"\(servicePath)\""
    let (success, output) = runShellCommand(command)
    if success {
      menuState.connected = true
      menuState.nodeName = nodeName
      refreshMenuUI()
      notifyFlutterMenuAction(action: "connectionStateChanged", payload: [
        "connected": true,
        "nodeName": nodeName,
        "proxyMode": menuState.proxyMode.rawValue
      ])
      logToFlutter("info", "状态栏启动加速成功: \(nodeName)")
      return true
    }
    logToFlutter("error", "状态栏启动加速失败: \(output)")
    return false
  }

  @discardableResult
  private func stopServiceForNode(_ nodeName: String) -> Bool {
    guard let serviceName = serviceNameForNode(nodeName) else { return false }
    let servicePath = "/Users/\(NSUserName())/Library/LaunchAgents/\(serviceName)"
    let uid = getuid()
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let useModernLaunchctl = os.majorVersion >= 11 || (os.majorVersion == 10 && os.minorVersion >= 15)
    let command = useModernLaunchctl
      ? "launchctl bootout gui/\(uid) \"\(servicePath)\""
      : "launchctl unload \"\(servicePath)\""
    let (success, output) = runShellCommand(command)
    if success {
      menuState.connected = false
      refreshMenuUI()
      notifyFlutterMenuAction(action: "connectionStateChanged", payload: [
        "connected": false,
        "nodeName": nodeName,
        "proxyMode": menuState.proxyMode.rawValue
      ])
      logToFlutter("info", "状态栏停止加速成功: \(nodeName)")
      return true
    }
    logToFlutter("error", "状态栏停止加速失败: \(output)")
    return false
  }

  private func runShellCommand(_ command: String) -> (Bool, String) {
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

  private func resolveTargetNodeName() -> String? {
    if menuState.nodeName != "-" && !menuState.nodeName.isEmpty {
      return menuState.nodeName
    }
    if let first = loadNodeEntries().first?.name {
      menuState.nodeName = first
      refreshMenuUI()
      return first
    }
    return nil
  }

  private func serviceNameForNode(_ nodeName: String) -> String? {
    return loadNodeEntries().first(where: { $0.name == nodeName })?.serviceName
  }

  private func loadNodeEntries() -> [(name: String, serviceName: String)] {
    guard let rulesFile = resolveRulesFile(),
          let data = try? Data(contentsOf: rulesFile),
          let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }

    return object.compactMap { item in
      guard let name = item["name"] as? String,
            let serviceName = item["serviceName"] as? String,
            !name.isEmpty,
            !serviceName.isEmpty else {
        return nil
      }
      return (name, serviceName)
    }
  }

  private func resolveRulesFile() -> URL? {
    let fileManager = FileManager.default
    let bundleId = Bundle.main.bundleIdentifier ?? "com.xstream"
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }

    let candidates = [
      appSupport.appendingPathComponent("\(bundleId)/vpn_nodes.json"),
      appSupport.appendingPathComponent("vpn_nodes.json")
    ]
    return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
  }

  private func resolveLogsDirectory() -> URL? {
    let fileManager = FileManager.default
    let bundleId = Bundle.main.bundleIdentifier ?? "com.xstream"
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }

    let candidates = [
      appSupport.appendingPathComponent("\(bundleId)/logs", isDirectory: true),
      appSupport.appendingPathComponent("logs", isDirectory: true)
    ]
    return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
  }

  private func notifyFlutterMenuAction(action: String, payload: [String: Any] = [:]) {
    DispatchQueue.main.async {
      self.nativeChannel?.invokeMethod("nativeMenuAction", arguments: [
        "action": action,
        "payload": payload
      ])
    }
  }

  private func handleUpdateMenuState(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing menu args", details: nil))
      return
    }

    if let connected = args["connected"] as? Bool {
      menuState.connected = connected
    }
    if let nodeName = args["nodeName"] as? String, !nodeName.isEmpty {
      menuState.nodeName = nodeName
    }
    if let mode = args["proxyMode"] as? String {
      menuState.proxyMode = (mode == "proxyOnly" || mode == "仅代理") ? .proxyOnly : .tun
    }
    refreshMenuUI()
    result("success")
  }

  private func isLaunchAtLoginEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return false
  }

  private func setLaunchAtLoginEnabled(_ enabled: Bool) -> Bool {
    guard #available(macOS 13.0, *) else {
      return false
    }

    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return true
    } catch {
      logToFlutter("error", "设置开机启动失败: \(error.localizedDescription)")
      return false
    }
  }
}
