import Foundation
import NetworkExtension
import FlutterMacOS
import Darwin

extension AppDelegate {
  func handlePacketTunnel(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startPacketTunnel":
      startPacketTunnel(result: result)
    case "stopPacketTunnel":
      stopPacketTunnel(result: result)
    case "getPacketTunnelStatus":
      getPacketTunnelStatus(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startPacketTunnel(result: @escaping FlutterResult) {
    loadOrCreateTunnelManager { manager, error in
      if let error = error {
        result("启动失败: \(error.localizedDescription)")
        return
      }
      guard let manager = manager else {
        result("启动失败: 未找到可用的 VPN 配置")
        return
      }
      do {
        try manager.connection.startVPNTunnel()
        result("已发送启动请求")
      } catch {
        result("启动失败: \(error.localizedDescription)")
      }
    }
  }

  private func stopPacketTunnel(result: @escaping FlutterResult) {
    loadTunnelManager { manager, error in
      if let error = error {
        result("停止失败: \(error.localizedDescription)")
        return
      }
      guard let manager = manager else {
        result("未配置 VPN")
        return
      }
      manager.connection.stopVPNTunnel()
      result("已发送停止请求")
    }
  }

  private func getPacketTunnelStatus(result: @escaping FlutterResult) {
    loadTunnelManager { manager, error in
      let utunList = self.listUtunInterfaces()
      if let _ = error {
        result([
          "status": "unknown",
          "utun": utunList
        ])
        return
      }
      guard let manager = manager else {
        result([
          "status": "not_configured",
          "utun": utunList
        ])
        return
      }
      result([
        "status": self.mapStatus(manager.connection.status),
        "utun": utunList
      ])
    }
  }

  private func loadTunnelManager(completion: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error = error {
        completion(nil, error)
        return
      }
      let providerId = self.packetTunnelProviderBundleId()
      let manager = managers?.first(where: { mgr in
        guard let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol else {
          return false
        }
        return proto.providerBundleIdentifier == providerId
      }) ?? managers?.first
      completion(manager, nil)
    }
  }

  private func loadOrCreateTunnelManager(completion: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error = error {
        completion(nil, error)
        return
      }

      let providerId = self.packetTunnelProviderBundleId()
      if let manager = managers?.first(where: { mgr in
        guard let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol else {
          return false
        }
        return proto.providerBundleIdentifier == providerId
      }) {
        completion(manager, nil)
        return
      }

      guard let providerId = providerId else {
        completion(nil, NSError(domain: "Xstream", code: -1, userInfo: [
          NSLocalizedDescriptionKey: "Missing PacketTunnel provider bundle id"
        ]))
        return
      }

      let manager = NETunnelProviderManager()
      let proto = NETunnelProviderProtocol()
      proto.providerBundleIdentifier = providerId
      proto.serverAddress = "Xstream"

      manager.protocolConfiguration = proto
      manager.localizedDescription = "Xstream VPN"
      manager.isEnabled = true

      manager.saveToPreferences { saveError in
        if let saveError = saveError {
          completion(nil, saveError)
          return
        }
        manager.loadFromPreferences { loadError in
          if let loadError = loadError {
            completion(nil, loadError)
            return
          }
          completion(manager, nil)
        }
      }
    }
  }

  private func packetTunnelProviderBundleId() -> String? {
    if let value = Bundle.main.object(forInfoDictionaryKey: "PacketTunnelProviderBundleId") as? String,
       !value.isEmpty {
      return value
    }
    guard let bundleId = Bundle.main.bundleIdentifier else {
      return nil
    }
    return "\(bundleId).PacketTunnel"
  }

  private func mapStatus(_ status: NEVPNStatus) -> String {
    switch status {
    case .connected:
      return "connected"
    case .connecting:
      return "connecting"
    case .disconnected:
      return "disconnected"
    case .disconnecting:
      return "disconnecting"
    case .invalid:
      return "invalid"
    case .reasserting:
      return "reasserting"
    @unknown default:
      return "unknown"
    }
  }

  private func listUtunInterfaces() -> [String] {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
      return []
    }
    defer { freeifaddrs(ifaddr) }
    var ptr = firstAddr
    var names = Set<String>()
    while true {
      let name = String(cString: ptr.pointee.ifa_name)
      if name.hasPrefix("utun") {
        names.insert(name)
      }
      guard let next = ptr.pointee.ifa_next else {
        break
      }
      ptr = next
    }
    return names.sorted()
  }
}
