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

  enum MenuLanguage {
    case zh
    case en
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
  private var menuLanguage: MenuLanguage = .zh

  private var statusLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private var nodeLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private var startStopItem = NSMenuItem(title: "", action: #selector(toggleAcceleration), keyEquivalent: "")
  private var reconnectItem = NSMenuItem(title: "", action: #selector(reconnectAcceleration), keyEquivalent: "")
  private var tunModeItem = NSMenuItem(title: "", action: #selector(selectTunMode), keyEquivalent: "")
  private var proxyOnlyModeItem = NSMenuItem(title: "", action: #selector(selectProxyOnlyMode), keyEquivalent: "")
  private var launchAtLoginItem = NSMenuItem(title: "", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
  private var proxyModeRootItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private var showWindowItem = NSMenuItem(title: "", action: #selector(showMainWindowAndNotify), keyEquivalent: "")
  private var quitStopItem = NSMenuItem(title: "", action: #selector(quitAndStopAcceleration), keyEquivalent: "q")

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

  override func applicationWillTerminate(_ notification: Notification) {
    // Rely on Dart FFI to stop node service if needed, or it simply exits with the app.
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

    let proxyModeMenu = NSMenu(title: "")
    tunModeItem.target = self
    proxyOnlyModeItem.target = self
    proxyModeMenu.addItem(tunModeItem)
    proxyModeMenu.addItem(proxyOnlyModeItem)
    proxyModeRootItem.submenu = proxyModeMenu
    menu.addItem(proxyModeRootItem)
    menu.addItem(NSMenuItem.separator())

    showWindowItem.target = self
    menu.addItem(showWindowItem)

    launchAtLoginItem.target = self
    menu.addItem(launchAtLoginItem)
    menu.addItem(NSMenuItem.separator())

    quitStopItem.target = self
    menu.addItem(quitStopItem)

    return menu
  }

  private func refreshMenuUI() {
    statusLineItem.title = "\(menuText(.status)): \(menuState.connected ? menuText(.connected) : menuText(.disconnected))"
    nodeLineItem.title = "\(menuText(.node)): \(menuState.nodeName)"
    startStopItem.title = menuState.connected ? menuText(.stopAcceleration) : menuText(.startAcceleration)
    reconnectItem.title = menuText(.reconnect)
    tunModeItem.title = menuText(.tunMode)
    proxyOnlyModeItem.title = menuText(.proxyOnlyMode)
    proxyModeRootItem.title = menuText(.proxyMode)
    showWindowItem.title = menuText(.showMainWindow)
    launchAtLoginItem.title = menuText(.launchAtLogin)
    quitStopItem.title = menuText(.quitAndStopAcceleration)
    reconnectItem.isEnabled = menuState.nodeName != "-" && !menuState.nodeName.isEmpty
    tunModeItem.state = menuState.proxyMode == .tun ? .on : .off
    proxyOnlyModeItem.state = menuState.proxyMode == .proxyOnly ? .on : .off
    launchAtLoginItem.state = menuState.launchAtLogin ? .on : .off
  }

  private enum MenuTextKey {
    case status
    case connected
    case disconnected
    case node
    case startAcceleration
    case stopAcceleration
    case reconnect
    case tunMode
    case proxyOnlyMode
    case proxyMode
    case showMainWindow
    case launchAtLogin
    case quitAndStopAcceleration
  }

  private func menuText(_ key: MenuTextKey) -> String {
    switch menuLanguage {
    case .zh:
      switch key {
      case .status: return "状态"
      case .connected: return "已连接"
      case .disconnected: return "未连接"
      case .node: return "节点"
      case .startAcceleration: return "启动加速"
      case .stopAcceleration: return "停止加速"
      case .reconnect: return "重新连接"
      case .tunMode: return "隧道模式"
      case .proxyOnlyMode: return "代理模式"
      case .proxyMode: return "代理模式"
      case .showMainWindow: return "显示主窗口"
      case .launchAtLogin: return "登录时启动"
      case .quitAndStopAcceleration: return "退出并停止加速"
      }
    case .en:
      switch key {
      case .status: return "Status"
      case .connected: return "Connected"
      case .disconnected: return "Disconnected"
      case .node: return "Node"
      case .startAcceleration: return "Start Acceleration"
      case .stopAcceleration: return "Stop Acceleration"
      case .reconnect: return "Reconnect"
      case .tunMode: return "Tunnel Mode"
      case .proxyOnlyMode: return "Proxy Mode"
      case .proxyMode: return "Proxy Mode"
      case .showMainWindow: return "Show Main Window"
      case .launchAtLogin: return "Launch at Login"
      case .quitAndStopAcceleration: return "Quit & Stop Acceleration"
      }
    }
  }

  @objc private func showMainWindowAndNotify() {
    showMainWindow()
    notifyFlutterMenuAction(action: "showMainWindow")
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
    notifyFlutterMenuAction(action: "reconnectAcceleration", payload: [
      "nodeName": node,
      "proxyMode": menuState.proxyMode.rawValue,
    ])
  }

  @objc private func quitAndStopAcceleration() {
    if menuState.connected {
      notifyFlutterMenuAction(action: "stopAcceleration", payload: [
        "nodeName": menuState.nodeName == "-" ? "" : menuState.nodeName,
        "proxyMode": menuState.proxyMode.rawValue,
      ])
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        NSApp.terminate(nil)
      }
      return
    }
    NSApp.terminate(nil)
  }

  private func startAcceleration() {
    notifyFlutterMenuAction(action: "startAcceleration", payload: [
      "nodeName": resolveTargetNodeName() ?? "",
      "proxyMode": menuState.proxyMode.rawValue,
    ])
  }

  private func stopAcceleration() {
    notifyFlutterMenuAction(action: "stopAcceleration", payload: [
      "nodeName": menuState.nodeName == "-" ? "" : menuState.nodeName,
      "proxyMode": menuState.proxyMode.rawValue,
    ])
  }

  private func resolveTargetNodeName() -> String? {
    if menuState.nodeName != "-" && !menuState.nodeName.isEmpty {
      return menuState.nodeName
    }
    if let first = loadNodeNames().first {
      menuState.nodeName = first
      refreshMenuUI()
      return first
    }
    return nil
  }

  private func loadNodeNames() -> [String] {
    guard let rulesFile = resolveRulesFile(),
      let data = try? Data(contentsOf: rulesFile),
      let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      return []
    }

    return object.compactMap { item in
      let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let name, !name.isEmpty else {
        return nil
      }
      return name
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
    if let languageCode = args["languageCode"] as? String {
      let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      menuLanguage = normalized.hasPrefix("zh") ? .zh : .en
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
