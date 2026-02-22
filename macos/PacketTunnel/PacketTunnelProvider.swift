import Foundation
import Network
import NetworkExtension
import Darwin

class PacketTunnelProvider: NEPacketTunnelProvider {
  private var activeSettings: NEPacketTunnelNetworkSettings?
  private let monitor = NWPathMonitor(prohibitedInterfaceTypes: [NWInterface.InterfaceType.other])
  private let statusStore = PacketTunnelStatusStore()
  private let engine: SecureTunnelEngine = XrayTunnelEngine()

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    do {
      let map = try resolveOptions(options: options)
      let enableIPv6 = shouldEnableIPv6(options: map, launchOptions: options)
      let settings = try buildNetworkSettings(options: map, enableIPv6: enableIPv6)

      setTunnelNetworkSettings(settings) { [weak self] error in
        guard let self else {
          completionHandler(error)
          return
        }

        if let error {
          self.statusStore.markFailed(error.localizedDescription)
          completionHandler(error)
          return
        }

        self.activeSettings = settings
        self.startPathMonitor()

        let fd = self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 ?? -1

        do {
          let configData = self.resolveConfigData(options: map)
          try self.engine.start(config: configData, fd: fd)
          self.statusStore.markConnected()
          completionHandler(nil)
        } catch {
          self.rollbackStartFailure(error: error, completionHandler: completionHandler)
        }
      }
    } catch {
      statusStore.markFailed(error.localizedDescription)
      completionHandler(error)
    }
  }

  override func stopTunnel(with _: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    monitor.cancel()
    engine.stop()
    statusStore.markDisconnected()
    completionHandler()
  }

  private func resolveOptions(options: [String: NSObject]?) throws -> [String: NSObject] {
    if let options {
      return options
    }

    let proto = protocolConfiguration as? NETunnelProviderProtocol
    if let map = proto?.providerConfiguration?["options"] as? [String: NSObject] {
      return map
    }

    throw NSError(
      domain: "Xstream.PacketTunnel",
      code: -1,
      userInfo: [NSLocalizedDescriptionKey: "Missing Packet Tunnel options"]
    )
  }

  private func resolveConfigData(options: [String: NSObject]) -> Data {
    if let data = options["config"] as? Data {
      return data
    }
    if let data = options["config"] as? NSData {
      return data as Data
    }
    return Data()
  }

  private func shouldEnableIPv6(options: [String: NSObject], launchOptions: [String: NSObject]?) -> Bool {
    let tun46Setting = (options["tun46Setting"] as? NSNumber)?.intValue ?? 2
    switch tun46Setting {
    case 0:
      return false
    case 1:
      return true
    default:
      if launchOptions != nil {
        return (options["defaultNicSupport6"] as? NSNumber)?.boolValue ?? true
      }
      return true
    }
  }

  private func buildNetworkSettings(
    options: [String: NSObject],
    enableIPv6: Bool
  ) throws -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    settings.mtu = options["mtu"] as? NSNumber ?? NSNumber(value: 1500)

    var dnsServers = (options["dnsServers4"] as? [String]) ?? []
    if enableIPv6 {
      dnsServers.append(contentsOf: (options["dnsServers6"] as? [String]) ?? [])
    }
    if dnsServers.isEmpty {
      dnsServers = ["1.1.1.1", "8.8.8.8"]
    }
    settings.dnsSettings = NEDNSSettings(servers: dnsServers)
    settings.dnsSettings?.matchDomains = [""]
    settings.dnsSettings?.matchDomainsNoSearch = true

    let ipv4Addresses = (options["ipv4Addresses"] as? [String]) ?? ["10.0.0.2"]
    let ipv4Masks = (options["ipv4SubnetMasks"] as? [String]) ?? ["255.255.255.0"]
    guard ipv4Addresses.count == ipv4Masks.count else {
      throw NSError(
        domain: "Xstream.PacketTunnel",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Invalid IPv4 subnet mask mapping"]
      )
    }

    let ipv4 = NEIPv4Settings(addresses: ipv4Addresses, subnetMasks: ipv4Masks)
    let ipv4Included = (options["ipv4IncludedRoutes"] as? [[String: String]]) ?? [[
      "destinationAddress": "0.0.0.0",
      "subnetMask": "0.0.0.0",
    ]]
    ipv4.includedRoutes = ipv4Included.compactMap { route in
      guard
        let destinationAddress = route["destinationAddress"],
        let subnetMask = route["subnetMask"]
      else {
        return nil
      }
      return NEIPv4Route(destinationAddress: destinationAddress, subnetMask: subnetMask)
    }

    let ipv4Excluded = (options["ipv4ExcludedRoutes"] as? [[String: String]])
      ?? (options["ipv4ExcludedRouteAddresses"] as? [[String: String]])
    if let ipv4Excluded {
      ipv4.excludedRoutes = ipv4Excluded.compactMap { route in
        guard
          let destinationAddress = route["destinationAddress"],
          let subnetMask = route["subnetMask"]
        else {
          return nil
        }
        return NEIPv4Route(destinationAddress: destinationAddress, subnetMask: subnetMask)
      }
    }
    settings.ipv4Settings = ipv4

    if enableIPv6 {
      let ipv6Addresses = (options["ipv6Addresses"] as? [String]) ?? ["fd00::2"]
      let ipv6Prefixes = (options["ipv6NetworkPrefixLengths"] as? [Int]) ?? [120]
      if ipv6Addresses.count == ipv6Prefixes.count {
        let ipv6 = NEIPv6Settings(
          addresses: ipv6Addresses,
          networkPrefixLengths: ipv6Prefixes.map { NSNumber(value: $0) }
        )

        let ipv6Included = (options["ipv6IncludedRoutes"] as? [[String: Any]]) ?? [[
          "destinationAddress": "::",
          "networkPrefixLength": NSNumber(value: 0),
        ]]
        ipv6.includedRoutes = parseIPv6Routes(ipv6Included)

        if let ipv6Excluded = options["ipv6ExcludedRoutes"] as? [[String: Any]] {
          ipv6.excludedRoutes = parseIPv6Routes(ipv6Excluded)
        }

        settings.ipv6Settings = ipv6
      }
    }

    return settings
  }

  private func parseIPv6Routes(_ rawRoutes: [[String: Any]]) -> [NEIPv6Route] {
    rawRoutes.compactMap { route in
      guard let destinationAddress = route["destinationAddress"] as? String else {
        return nil
      }
      if let prefix = route["networkPrefixLength"] as? NSNumber {
        return NEIPv6Route(destinationAddress: destinationAddress, networkPrefixLength: prefix)
      }
      if let prefix = route["networkPrefixLength"] as? Int {
        return NEIPv6Route(
          destinationAddress: destinationAddress,
          networkPrefixLength: NSNumber(value: prefix)
        )
      }
      return nil
    }
  }

  private func startPathMonitor() {
    monitor.pathUpdateHandler = { path in
      guard path.status == .satisfied else {
        return
      }
      _ = path.availableInterfaces.first(where: { !$0.name.contains("utun") })
    }
    monitor.start(queue: DispatchQueue.global())
  }

  private func rollbackStartFailure(
    error: Error,
    completionHandler: @escaping (Error?) -> Void
  ) {
    engine.stop()
    monitor.cancel()
    activeSettings = nil
    statusStore.markFailed(error.localizedDescription)
    completionHandler(error)
  }
}

private protocol SecureTunnelEngine {
  func start(config: Data, fd: Int32) throws
  func stop()
}

private final class XrayTunnelEngine: SecureTunnelEngine {
  private let bridge = XrayTunnelBridge()
  private var tunnelHandle: Int64?

  func start(config: Data, fd: Int32) throws {
    stop()
    guard !config.isEmpty else {
      throw NSError(
        domain: "Xstream.PacketTunnel",
        code: -10,
        userInfo: [NSLocalizedDescriptionKey: "Missing Xray config for Packet Tunnel"]
      )
    }

    let handle = try bridge.start(configData: config, fd: fd)
    tunnelHandle = handle
  }

  func stop() {
    if let handle = tunnelHandle {
      bridge.stop(handle: handle)
      bridge.free(handle: handle)
      tunnelHandle = nil
    }
  }
}

private final class XrayTunnelBridge {
  private typealias StartXrayTunnelWithFdFn = @convention(c) (UnsafePointer<CChar>?, Int32) -> Int64
  private typealias StopXrayTunnelFn = @convention(c) (Int64) -> UnsafeMutablePointer<CChar>?
  private typealias FreeXrayTunnelFn = @convention(c) (Int64) -> UnsafeMutablePointer<CChar>?
  private typealias FreeCStringFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

  private let startFn: StartXrayTunnelWithFdFn?
  private let stopFn: StopXrayTunnelFn?
  private let freeTunnelFn: FreeXrayTunnelFn?
  private let freeCStringFn: FreeCStringFn?
  private let dlHandle: UnsafeMutableRawPointer?

  init() {
    dlHandle = dlopen(nil, RTLD_NOW)
    startFn = XrayTunnelBridge.loadSymbol("StartXrayTunnelWithFd", from: dlHandle)
    stopFn = XrayTunnelBridge.loadSymbol("StopXrayTunnel", from: dlHandle)
    freeTunnelFn = XrayTunnelBridge.loadSymbol("FreeXrayTunnel", from: dlHandle)
    freeCStringFn = XrayTunnelBridge.loadSymbol("FreeCString", from: dlHandle)
  }

  deinit {
    if let dlHandle {
      dlclose(dlHandle)
    }
  }

  func start(configData: Data, fd: Int32) throws -> Int64 {
    guard let startFn else {
      throw NSError(
        domain: "Xstream.PacketTunnel",
        code: -11,
        userInfo: [NSLocalizedDescriptionKey: "StartXrayTunnelWithFd symbol is unavailable"]
      )
    }
    let json = String(data: configData, encoding: .utf8) ?? "{}"
    return try json.withCString { cstr in
      let handle = startFn(cstr, fd)
      if handle <= 0 {
        throw NSError(
          domain: "Xstream.PacketTunnel",
          code: -12,
          userInfo: [NSLocalizedDescriptionKey: "StartXrayTunnelWithFd returned invalid handle"]
        )
      }
      return handle
    }
  }

  func stop(handle: Int64) {
    guard let stopFn else {
      return
    }
    let message = stopFn(handle)
    releaseCString(message)
  }

  func free(handle: Int64) {
    guard let freeTunnelFn else {
      return
    }
    let message = freeTunnelFn(handle)
    releaseCString(message)
  }

  private func releaseCString(_ ptr: UnsafeMutablePointer<CChar>?) {
    guard let ptr else {
      return
    }
    if let freeCStringFn {
      freeCStringFn(ptr)
    } else {
      Darwin.free(ptr)
    }
  }

  private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer?) -> T? {
    guard let handle, let symbol = dlsym(handle, name) else {
      return nil
    }
    return unsafeBitCast(symbol, to: T.self)
  }
}

private final class PacketTunnelStatusStore {
  private let defaults = UserDefaults(suiteName: "group.com.xstream") ?? .standard
  private let errorKey = "packet_tunnel_last_error"
  private let startedAtKey = "packet_tunnel_started_at"

  func markConnected() {
    defaults.removeObject(forKey: errorKey)
    defaults.set(Int64(Date().timeIntervalSince1970), forKey: startedAtKey)
  }

  func markFailed(_ error: String) {
    defaults.set(error, forKey: errorKey)
  }

  func markDisconnected() {
    defaults.removeObject(forKey: startedAtKey)
  }
}
