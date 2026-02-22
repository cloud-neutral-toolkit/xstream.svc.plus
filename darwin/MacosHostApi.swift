#if os(macOS)
import FlutterMacOS
import Cocoa
#else
import Flutter
#endif
import Foundation
import Network
import NetworkExtension
import Darwin

class DarwinHostApiImpl: DarwinHostApi {
  private let groupId = "group.plus.svc.xstream"
  private let profileOptionsKey = "packet_tunnel_profile_options"
  private let statusErrorKey = "packet_tunnel_last_error"
  private let statusStartedAtKey = "packet_tunnel_started_at"

  private let flutterApi: DarwinFlutterApi?

  init(binaryMessenger: FlutterBinaryMessenger? = nil) {
    if let binaryMessenger {
      flutterApi = DarwinFlutterApi(binaryMessenger: binaryMessenger)
    } else {
      flutterApi = nil
    }
  }

  func appGroupPath() throws -> String {
    guard
      let path = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: groupId
      )?.relativePath
    else {
      throw PigeonError(code: "nil-container-url", message: "App Group container not found", details: groupId)
    }
    return path
  }

  func startXApiServer(
    config _: FlutterStandardTypedData,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(
      .failure(
        PigeonError(
          code: "unsupported",
          message: "XApi server is not integrated in this Xstream build",
          details: nil
        )
      )
    )
  }

  func redirectStdErr(path: String, completion: @escaping (Result<Void, Error>) -> Void) {
    FileManager.default.createFile(atPath: path, contents: nil)
    if freopen(path, "a+", stderr) != nil {
      completion(.success(()))
      return
    }
    completion(
      .failure(
        PigeonError(
          code: "redirect-failed",
          message: "Failed to redirect stderr",
          details: path
        )
      )
    )
  }

  func generateTls() throws -> FlutterStandardTypedData {
    throw PigeonError(
      code: "unsupported",
      message: "TLS generation is not integrated in this Xstream build",
      details: nil
    )
  }

  func setupShutdownNotification() throws {
    #if os(macOS)
    let workspace = NSWorkspace.shared
    let notificationCenter = workspace.notificationCenter

    notificationCenter.addObserver(
      forName: NSWorkspace.willPowerOffNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.flutterApi?.onSystemWillShutdown(completion: { _ in })
    }

    notificationCenter.addObserver(
      forName: NSWorkspace.sessionDidResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.flutterApi?.onSystemWillRestart(completion: { _ in })
    }

    notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.flutterApi?.onSystemWillSleep(completion: { _ in })
    }

    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.flutterApi?.onSystemWillShutdown(completion: { _ in })
    }
    #endif
  }

  func savePacketTunnelProfile(profile: TunnelProfile) throws -> String {
    let defaults = sharedDefaults()
    let options = buildPacketTunnelOptions(profile: profile)
    defaults.set(options, forKey: profileOptionsKey)
    defaults.removeObject(forKey: statusErrorKey)
    emitPacketTunnelStateChanged()
    return "profile_saved"
  }

  func startPacketTunnel(completion: @escaping (Result<Void, Error>) -> Void) {
    guard let options = storedPacketTunnelOptions() else {
      let error = PigeonError(
        code: "profile-missing",
        message: "Packet Tunnel profile is missing",
        details: nil
      )
      writeLastError(error.localizedDescription)
      emitPacketTunnelError(code: "profile-missing", message: error.localizedDescription)
      completion(.failure(error))
      return
    }

    loadOrCreateTunnelManager { manager, error in
      if let error {
        self.writeLastError(error.localizedDescription)
        self.emitPacketTunnelError(code: "manager-load-failed", message: error.localizedDescription)
        completion(.failure(error))
        return
      }
      guard let manager else {
        let managerError = PigeonError(
          code: "manager-unavailable",
          message: "No available Packet Tunnel manager",
          details: nil
        )
        self.writeLastError(managerError.localizedDescription)
        self.emitPacketTunnelError(code: "manager-unavailable", message: managerError.localizedDescription)
        completion(.failure(managerError))
        return
      }

      self.prepareManagerWithLatestOptions(manager: manager, options: options) { prepared, prepareError in
        if let prepareError {
          self.writeLastError(prepareError.localizedDescription)
          self.emitPacketTunnelError(code: "manager-prepare-failed", message: prepareError.localizedDescription)
          completion(.failure(prepareError))
          return
        }
        guard let prepared else {
          let preparedError = PigeonError(
            code: "manager-prepare-failed",
            message: "Packet Tunnel manager was not prepared",
            details: nil
          )
          self.writeLastError(preparedError.localizedDescription)
          self.emitPacketTunnelError(code: "manager-prepare-failed", message: preparedError.localizedDescription)
          completion(.failure(preparedError))
          return
        }

        do {
          try prepared.connection.startVPNTunnel(options: options)
          self.clearLastError()
          self.writeStartedAt(Int64(Date().timeIntervalSince1970))
          self.emitPacketTunnelStateChanged()
          completion(.success(()))
        } catch {
          self.writeLastError(error.localizedDescription)
          self.emitPacketTunnelError(code: "start-failed", message: error.localizedDescription)
          completion(.failure(error))
        }
      }
    }
  }

  func stopPacketTunnel(completion: @escaping (Result<Void, Error>) -> Void) {
    loadTunnelManager { manager, error in
      if let error {
        self.writeLastError(error.localizedDescription)
        self.emitPacketTunnelError(code: "manager-load-failed", message: error.localizedDescription)
        completion(.failure(error))
        return
      }
      guard let manager else {
        self.clearStartedAt()
        self.emitPacketTunnelStateChanged()
        completion(.success(()))
        return
      }
      manager.connection.stopVPNTunnel()
      self.clearStartedAt()
      self.emitPacketTunnelStateChanged()
      completion(.success(()))
    }
  }

  func getPacketTunnelStatus() throws -> TunnelStatus {
    let manager = try loadTunnelManagerSync()
    let state: String
    if let manager {
      state = mapStatus(manager.connection.status)
    } else {
      state = "not_configured"
    }

    return TunnelStatus(
      state: state,
      lastError: readLastError(),
      utunInterfaces: listUtunInterfaces(),
      startedAt: readStartedAt()
    )
  }

  private func sharedDefaults() -> UserDefaults {
    UserDefaults(suiteName: groupId) ?? .standard
  }

  private func storedPacketTunnelOptions() -> [String: NSObject]? {
    if let map = sharedDefaults().dictionary(forKey: profileOptionsKey) as? [String: NSObject] {
      return map
    }
    guard let dictionary = sharedDefaults().dictionary(forKey: profileOptionsKey) else {
      return nil
    }
    var result: [String: NSObject] = [:]
    for (key, value) in dictionary {
      if let object = value as? NSObject {
        result[key] = object
      }
    }
    return result.isEmpty ? nil : result
  }

  private func buildPacketTunnelOptions(profile: TunnelProfile) -> [String: NSObject] {
    var options: [String: NSObject] = [
      "useFd": NSNumber(value: false),
      "tun46Setting": NSNumber(value: profile.tun46Setting),
      "defaultNicSupport6": NSNumber(value: profile.defaultNicSupport6),
      "mtu": NSNumber(value: profile.mtu),
      "dnsServers4": NSArray(array: profile.dnsServers4),
      "dnsServers6": NSArray(array: profile.dnsServers6),
      "ipv4Addresses": NSArray(array: profile.ipv4Addresses),
      "ipv4SubnetMasks": NSArray(array: profile.ipv4SubnetMasks),
      "ipv4IncludedRoutes": NSArray(array: profile.ipv4IncludedRoutes.map { route in
        [
          "destinationAddress": route.destinationAddress,
          "subnetMask": route.subnetMask,
        ] as NSDictionary
      }),
      "ipv4ExcludedRoutes": NSArray(array: profile.ipv4ExcludedRoutes.map { route in
        [
          "destinationAddress": route.destinationAddress,
          "subnetMask": route.subnetMask,
        ] as NSDictionary
      }),
      "ipv4ExcludedRouteAddresses": NSArray(array: profile.ipv4ExcludedRoutes.map { route in
        [
          "destinationAddress": route.destinationAddress,
          "subnetMask": route.subnetMask,
        ] as NSDictionary
      }),
      "ipv6Addresses": NSArray(array: profile.ipv6Addresses),
      "ipv6NetworkPrefixLengths": NSArray(array: profile.ipv6NetworkPrefixLengths.map(NSNumber.init(value:))),
      "ipv6IncludedRoutes": NSArray(array: profile.ipv6IncludedRoutes.map { route in
        [
          "destinationAddress": route.destinationAddress,
          "networkPrefixLength": NSNumber(value: route.networkPrefixLength),
        ] as NSDictionary
      }),
      "ipv6ExcludedRoutes": NSArray(array: profile.ipv6ExcludedRoutes.map { route in
        [
          "destinationAddress": route.destinationAddress,
          "networkPrefixLength": NSNumber(value: route.networkPrefixLength),
        ] as NSDictionary
      }),
    ]

    let configURL = URL(fileURLWithPath: profile.configPath)
    if let data = try? Data(contentsOf: configURL), !data.isEmpty {
      options["config"] = data as NSData
    }

    return options
  }

  private func packetTunnelProviderBundleId() -> String? {
    if let value = Bundle.main.object(forInfoDictionaryKey: "PacketTunnelProviderBundleId") as? String,
       !value.isEmpty
    {
      return value
    }
    guard let bundleId = Bundle.main.bundleIdentifier else {
      return nil
    }
    return "\(bundleId).PacketTunnel"
  }

  private func loadTunnelManager(completion: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
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
      if let error {
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

      guard let providerId else {
        completion(nil, NSError(domain: "Xstream.PacketTunnel", code: -1, userInfo: [
          NSLocalizedDescriptionKey: "Missing PacketTunnel provider bundle id",
        ]))
        return
      }

      let manager = NETunnelProviderManager()
      let proto = NETunnelProviderProtocol()
      proto.providerBundleIdentifier = providerId
      proto.serverAddress = "Xstream Secure Tunnel"
      proto.providerConfiguration = [
        "options": self.storedPacketTunnelOptions() ?? [:],
      ]

      manager.protocolConfiguration = proto
      manager.localizedDescription = "Xstream Secure Tunnel"
      manager.isEnabled = true

      manager.saveToPreferences { saveError in
        if let saveError {
          completion(nil, saveError)
          return
        }
        manager.loadFromPreferences { loadError in
          if let loadError {
            completion(nil, loadError)
            return
          }
          completion(manager, nil)
        }
      }
    }
  }

  private func prepareManagerWithLatestOptions(
    manager: NETunnelProviderManager,
    options: [String: NSObject],
    completion: @escaping (NETunnelProviderManager?, Error?) -> Void
  ) {
    guard let providerId = packetTunnelProviderBundleId() else {
      completion(nil, NSError(domain: "Xstream.PacketTunnel", code: -1, userInfo: [
        NSLocalizedDescriptionKey: "Missing PacketTunnel provider bundle id",
      ]))
      return
    }

    let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
    proto.providerBundleIdentifier = providerId
    proto.serverAddress = "Xstream Secure Tunnel"
    proto.providerConfiguration = [
      "options": options,
    ]

    manager.protocolConfiguration = proto
    manager.localizedDescription = "Xstream Secure Tunnel"
    manager.isEnabled = true

    manager.saveToPreferences { saveError in
      if let saveError {
        completion(nil, saveError)
        return
      }
      manager.loadFromPreferences { loadError in
        if let loadError {
          completion(nil, loadError)
          return
        }
        completion(manager, nil)
      }
    }
  }

  private func loadTunnelManagerSync(timeoutSeconds: TimeInterval = 3.0) throws -> NETunnelProviderManager? {
    var outputManager: NETunnelProviderManager?
    var outputError: Error?
    let semaphore = DispatchSemaphore(value: 0)

    loadTunnelManager { manager, error in
      outputManager = manager
      outputError = error
      semaphore.signal()
    }

    if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
      throw PigeonError(code: "manager-timeout", message: "Timed out while loading Packet Tunnel manager", details: nil)
    }

    if let outputError {
      throw outputError
    }

    return outputManager
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

  private func writeStartedAt(_ timestamp: Int64) {
    sharedDefaults().set(timestamp, forKey: statusStartedAtKey)
  }

  private func clearStartedAt() {
    sharedDefaults().removeObject(forKey: statusStartedAtKey)
  }

  private func readStartedAt() -> Int64? {
    if let value = sharedDefaults().object(forKey: statusStartedAtKey) as? Int64 {
      return value
    }
    if let value = sharedDefaults().object(forKey: statusStartedAtKey) as? Int {
      return Int64(value)
    }
    if let value = sharedDefaults().object(forKey: statusStartedAtKey) as? NSNumber {
      return value.int64Value
    }
    return nil
  }

  private func writeLastError(_ message: String) {
    sharedDefaults().set(message, forKey: statusErrorKey)
  }

  private func clearLastError() {
    sharedDefaults().removeObject(forKey: statusErrorKey)
  }

  private func readLastError() -> String? {
    sharedDefaults().string(forKey: statusErrorKey)
  }

  private func emitPacketTunnelStateChanged() {
    guard let flutterApi else {
      return
    }

    guard let status = try? getPacketTunnelStatus() else {
      return
    }

    DispatchQueue.main.async {
      flutterApi.onPacketTunnelStateChanged(status: status, completion: { _ in })
    }
  }

  private func emitPacketTunnelError(code: String, message: String) {
    guard let flutterApi else {
      return
    }

    DispatchQueue.main.async {
      flutterApi.onPacketTunnelError(code: code, message: message, completion: { _ in })
    }
  }
}
