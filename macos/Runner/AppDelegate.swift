// AppDelegate.swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var statusItem: NSStatusItem?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let window = mainFlutterWindow,
       let controller = window.contentViewController as? FlutterViewController {

      let channel = FlutterMethodChannel(name: "com.xstream/native", binaryMessenger: controller.engine.binaryMessenger)

      let bundleId = Bundle.main.bundleIdentifier ?? "com.xstream"

      channel.setMethodCallHandler { [self] call, result in
        switch call.method {
        case "writeConfigFiles":
          self.writeConfigFiles(call: call, result: result)

        case "startNodeService", "stopNodeService", "checkNodeStatus":
          self.handleServiceControl(call: call, bundleId: bundleId, result: result)
        case "setSystemProxy":
          self.handleSystemProxy(call: call, result: result)
        case "startPacketTunnel", "stopPacketTunnel", "getPacketTunnelStatus":
          self.handlePacketTunnel(call: call, result: result)

        case "performAction":
          self.handlePerformAction(call: call, bundleId: bundleId, result: result)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Create status bar item with custom icon
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem?.button {
      // Load the "StatusIcon" image from asset catalog
      button.image = NSImage(named: "StatusIcon") ?? NSApp.applicationIconImage
      button.action = #selector(toggleMainWindow)
      button.target = self
    }
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Show XStream", action: #selector(showMainWindow), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    statusItem?.menu = menu

    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Toggle visibility of the main Flutter window when clicking the status icon
  @objc func toggleMainWindow() {
    if let window = mainFlutterWindow {
      if window.isVisible {
        window.orderOut(nil)
      } else {
        showMainWindow()
      }
    }
  }

  @objc func showMainWindow() {
    if let window = mainFlutterWindow {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }
}
