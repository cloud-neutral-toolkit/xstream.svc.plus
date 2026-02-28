import Darwin
import Foundation
import Network
import NetworkExtension

#if os(macOS)
  import FlutterMacOS
  import Cocoa
#else
  import Flutter
#endif

class DarwinHostApiImpl: DarwinHostApi {
  private let groupId = "group.plus.svc.xstream"
  private let profileOptionsKey = "packet_tunnel_profile_options"
  private let statusErrorKey = "packet_tunnel_last_error"
  private let statusStartedAtKey = "packet_tunnel_started_at"
  private let packetTunnelDisplayName = "Xstream"

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
      throw PigeonError(
        code: "nil-container-url", message: "App Group container not found", details: groupId)
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

  func savePacketTunnelProfile(
    profile: TunnelProfile,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    let defaults = sharedDefaults()
    let previousOptions = storedPacketTunnelOptions()
    let options = buildPacketTunnelOptions(profile: profile)
    let staleManagerHint = readLastError()
    defaults.set(options, forKey: profileOptionsKey)
    defaults.removeObject(forKey: statusErrorKey)

    #if os(iOS)
      loadOrCreateTunnelManager(staleManagerHint: staleManagerHint) { manager, error in
        if let error {
          let errorMessage = self.describeError(error)
          self.writeLastError(errorMessage)
          self.emitPacketTunnelError(code: "profile-save-failed", message: errorMessage)
          self.emitPacketTunnelStateChanged()
          completion(
            .failure(
              PigeonError(
                code: "profile-save-failed",
                message: errorMessage,
                details: nil
              )
            )
          )
          return
        }

        guard let manager else {
          let error = PigeonError(
            code: "manager-unavailable",
            message: "No available Packet Tunnel manager",
            details: nil
          )
          let errorMessage = self.describeError(error)
          self.writeLastError(errorMessage)
          self.emitPacketTunnelError(code: "profile-save-failed", message: errorMessage)
          self.emitPacketTunnelStateChanged()
          completion(.failure(error))
          return
        }

        if let providerId = self.packetTunnelProviderBundleId(),
          self.packetTunnelOptionsEqual(previousOptions, options),
          self.managerHasLatestOptions(manager, providerId: providerId, options: options),
          !self.shouldForceManagerRecreation(staleManagerHint: staleManagerHint)
        {
          self.emitPacketTunnelStateChanged()
          completion(.success("profile_unchanged"))
          return
        }

        self.prepareManagerWithLatestOptions(manager: manager, options: options) {
          prepared, prepareError in
          if let prepareError {
            let errorMessage = self.describeError(prepareError)
            self.writeLastError(errorMessage)
            self.emitPacketTunnelError(code: "profile-save-failed", message: errorMessage)
            self.emitPacketTunnelStateChanged()
            completion(
              .failure(
                PigeonError(
                  code: "profile-save-failed",
                  message: errorMessage,
                  details: nil
                )
              )
            )
            return
          }

          guard prepared != nil else {
            let error = PigeonError(
              code: "manager-prepare-failed",
              message: "Packet Tunnel manager was not prepared",
              details: nil
            )
            let errorMessage = self.describeError(error)
            self.writeLastError(errorMessage)
            self.emitPacketTunnelError(code: "profile-save-failed", message: errorMessage)
            self.emitPacketTunnelStateChanged()
            completion(.failure(error))
            return
          }

          self.emitPacketTunnelStateChanged()
          completion(.success("profile_saved"))
        }
      }
    #else
      emitPacketTunnelStateChanged()
      completion(.success("profile_saved"))
    #endif
  }

  func startPacketTunnel(completion: @escaping (Result<Void, Error>) -> Void) {
    guard var options = storedPacketTunnelOptions() else {
      let error = PigeonError(
        code: "profile-missing",
        message: "Packet Tunnel profile is missing",
        details: nil
      )
      let errorMessage = describeError(error)
      writeLastError(errorMessage)
      emitPacketTunnelError(code: "profile-missing", message: errorMessage)
      completion(.failure(error))
      return
    }

    if let configPath = options["configPath"] as? String {
      let url = URL(fileURLWithPath: configPath)
      do {
        let data = try Data(contentsOf: url)
        if data.isEmpty {
          throw NSError(
            domain: "Xstream", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Config file is empty"])
        }
        options["config"] = data as NSData
      } catch {
        let errorMsg = "Failed to load config file at \(configPath): \(error.localizedDescription)"
        self.writeLastError(errorMsg)
        self.emitPacketTunnelError(code: "config-load-failed", message: errorMsg)
        completion(
          .failure(PigeonError(code: "config-load-failed", message: errorMsg, details: nil)))
        return
      }
    }

    let staleManagerHint = readLastError()
    loadOrCreateTunnelManager(staleManagerHint: staleManagerHint) { manager, error in
      if let error {
        let errorMessage = self.describeError(error)
        self.writeLastError(errorMessage)
        self.emitPacketTunnelError(code: "manager-load-failed", message: errorMessage)
        completion(.failure(error))
        return
      }
      guard let manager else {
        let managerError = PigeonError(
          code: "manager-unavailable",
          message: "No available Packet Tunnel manager",
          details: nil
        )
        let errorMessage = self.describeError(managerError)
        self.writeLastError(errorMessage)
        self.emitPacketTunnelError(
          code: "manager-unavailable", message: errorMessage)
        completion(.failure(managerError))
        return
      }

      self.prepareManagerWithLatestOptions(manager: manager, options: options) {
        prepared, prepareError in
        if let prepareError {
          let errorMessage = self.describeError(prepareError)
          self.writeLastError(errorMessage)
          self.emitPacketTunnelError(
            code: "manager-prepare-failed", message: errorMessage)
          completion(.failure(prepareError))
          return
        }
        guard let prepared else {
          let preparedError = PigeonError(
            code: "manager-prepare-failed",
            message: "Packet Tunnel manager was not prepared",
            details: nil
          )
          let errorMessage = self.describeError(preparedError)
          self.writeLastError(errorMessage)
          self.emitPacketTunnelError(
            code: "manager-prepare-failed", message: errorMessage)
          completion(.failure(preparedError))
          return
        }

        self.startPreparedPacketTunnel(
          manager: prepared,
          options: options,
          allowRepairOnIOS: true,
          completion: completion
        )
      }
    }
  }

  func stopPacketTunnel(completion: @escaping (Result<Void, Error>) -> Void) {
    loadTunnelManager { manager, error in
      if let error {
        let errorMessage = self.describeError(error)
        self.writeLastError(errorMessage)
        self.emitPacketTunnelError(code: "manager-load-failed", message: errorMessage)
        completion(.failure(error))
        return
      }
      guard let manager else {
        self.clearStartedAt()
        self.clearLastError()
        self.emitPacketTunnelStateChanged()
        completion(.success(()))
        return
      }
      manager.connection.stopVPNTunnel()
      self.clearStartedAt()
      self.clearLastError()
      self.emitPacketTunnelStateChanged()
      completion(.success(()))
    }
  }

  func getPacketTunnelStatus(completion: @escaping (Result<TunnelStatus, Error>) -> Void) {
    loadTunnelManager { manager, error in
      if let error {
        completion(.failure(error))
        return
      }

      let state: String
      if let manager {
        state = self.mapStatus(manager.connection.status)
      } else {
        state = "not_configured"
      }

      if !self.shouldExposeStartedAt(for: state) {
        self.clearStartedAt()
      }
      let startedAt = self.shouldExposeStartedAt(for: state) ? self.readStartedAt() : nil
      let utunInterfaces = self.listUtunInterfaces()

      self.resolveLastDisconnectError(manager: manager, state: state) { lastError in
        completion(
          .success(
            TunnelStatus(
              state: state,
              lastError: lastError,
              utunInterfaces: utunInterfaces,
              startedAt: startedAt
            )
          )
        )
      }
    }
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
      "tun46Setting": NSNumber(value: profile.tun46Setting),
      "defaultNicSupport6": NSNumber(value: profile.defaultNicSupport6),
      "mtu": NSNumber(value: profile.mtu),
      "dnsServers4": NSArray(array: profile.dnsServers4),
      "dnsServers6": NSArray(array: profile.dnsServers6),
      "ipv4Addresses": NSArray(array: profile.ipv4Addresses),
      "ipv4SubnetMasks": NSArray(array: profile.ipv4SubnetMasks),
      "ipv4IncludedRoutes": NSArray(
        array: profile.ipv4IncludedRoutes.map { route in
          [
            "destinationAddress": route.destinationAddress,
            "subnetMask": route.subnetMask,
          ] as NSDictionary
        }),
      "ipv4ExcludedRoutes": NSArray(
        array: profile.ipv4ExcludedRoutes.map { route in
          [
            "destinationAddress": route.destinationAddress,
            "subnetMask": route.subnetMask,
          ] as NSDictionary
        }),
      "ipv4ExcludedRouteAddresses": NSArray(
        array: profile.ipv4ExcludedRoutes.map { route in
          [
            "destinationAddress": route.destinationAddress,
            "subnetMask": route.subnetMask,
          ] as NSDictionary
        }),
      "ipv6Addresses": NSArray(array: profile.ipv6Addresses),
      "ipv6NetworkPrefixLengths": NSArray(
        array: profile.ipv6NetworkPrefixLengths.map(NSNumber.init(value:))),
      "ipv6IncludedRoutes": NSArray(
        array: profile.ipv6IncludedRoutes.map { route in
          [
            "destinationAddress": route.destinationAddress,
            "networkPrefixLength": NSNumber(value: route.networkPrefixLength),
          ] as NSDictionary
        }),
      "ipv6ExcludedRoutes": NSArray(
        array: profile.ipv6ExcludedRoutes.map { route in
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
    options["configPath"] = profile.configPath as NSString

    return options
  }

  private func packetTunnelProviderBundleId() -> String? {
    if let value = Bundle.main.object(forInfoDictionaryKey: "PacketTunnelProviderBundleId")
      as? String,
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
      })
      completion(manager, nil)
    }
  }

  private func loadOrCreateTunnelManager(
    staleManagerHint: String? = nil,
    completion: @escaping (NETunnelProviderManager?, Error?) -> Void
  ) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        completion(nil, error)
        return
      }

      guard let providerId = self.packetTunnelProviderBundleId() else {
        completion(
          nil,
          NSError(
            domain: "Xstream.PacketTunnel", code: -1,
            userInfo: [
              NSLocalizedDescriptionKey: "Missing PacketTunnel provider bundle id"
            ]))
        return
      }

      let allManagers = managers ?? []
      let matchingManagers = allManagers.filter { mgr in
        guard let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol else {
          return false
        }
        return proto.providerBundleIdentifier == providerId
      }
      let sameNameManagers = allManagers.filter { mgr in
        mgr.localizedDescription == self.packetTunnelDisplayName
      }
      let shouldForceRecreate = self.shouldForceManagerRecreation(
        staleManagerHint: staleManagerHint
      )

      if let manager = matchingManagers.first {
        let hasDuplicateMatches = matchingManagers.count > 1
        let hasStaleSameNameManagers = sameNameManagers.contains { mgr in
          guard let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol else {
            return true
          }
          return proto.providerBundleIdentifier != providerId
        }
        if hasDuplicateMatches
          || hasStaleSameNameManagers
          || shouldForceRecreate
          || self.shouldRecreateTunnelManager(manager, providerId: providerId)
        {
          self.recreateTunnelManager(providerId: providerId, completion: completion)
          return
        }
        completion(manager, nil)
        return
      }

      if !sameNameManagers.isEmpty {
        self.recreateTunnelManager(providerId: providerId, completion: completion)
        return
      }

      self.createTunnelManager(providerId: providerId, completion: completion)
    }
  }

  private func shouldRecreateTunnelManager(
    _ manager: NETunnelProviderManager,
    providerId: String?
  ) -> Bool {
    guard let providerId else {
      return false
    }
    guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else {
      return true
    }
    if proto.providerBundleIdentifier != providerId {
      return true
    }
    if manager.localizedDescription != packetTunnelDisplayName {
      return true
    }
    if proto.serverAddress != packetTunnelDisplayName {
      return true
    }
    if manager.connection.status == .invalid {
      return true
    }
    return false
  }

  private func shouldForceManagerRecreation(staleManagerHint: String?) -> Bool {
    #if os(iOS)
      return isPluginRegistrationError(staleManagerHint)
    #else
      _ = staleManagerHint
      return false
    #endif
  }

  private func packetTunnelOptionsEqual(_ lhs: [String: NSObject]?, _ rhs: [String: NSObject])
    -> Bool
  {
    guard let lhs else {
      return false
    }
    return NSDictionary(dictionary: lhs).isEqual(to: rhs)
  }

  private func managerHasLatestOptions(
    _ manager: NETunnelProviderManager,
    providerId: String,
    options: [String: NSObject]
  ) -> Bool {
    guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else {
      return false
    }
    guard proto.providerBundleIdentifier == providerId else {
      return false
    }
    guard manager.localizedDescription == packetTunnelDisplayName else {
      return false
    }
    guard proto.serverAddress == packetTunnelDisplayName else {
      return false
    }
    guard
      let currentOptions = packetTunnelOptions(
        from: proto.providerConfiguration?["options"] as? [String: Any])
    else {
      return false
    }
    return packetTunnelOptionsEqual(currentOptions, options)
  }

  private func packetTunnelOptions(from dictionary: [String: Any]?) -> [String: NSObject]? {
    guard let dictionary else {
      return nil
    }
    var result: [String: NSObject] = [:]
    for (key, value) in dictionary {
      guard let object = value as? NSObject else {
        return nil
      }
      result[key] = object
    }
    return result.isEmpty ? nil : result
  }

  // iOS can retain a stale System VPN profile after reinstall/update. When the
  // system reports that the VPN app needs to be updated, force a full manager
  // recreation so the profile binds to the current Packet Tunnel extension.
  private func isPluginRegistrationError(_ message: String?) -> Bool {
    guard let message else {
      return false
    }
    let normalized =
      message
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !normalized.isEmpty else {
      return false
    }
    if normalized.contains("domain=nevpnconnectionerrordomain")
      && normalized.contains("code=14")
    {
      return true
    }
    if normalized.contains("vpn app used by the vpn configuration is not installed") {
      return true
    }
    if normalized.contains("needed to be updated") {
      return true
    }
    return false
  }

  private func recreateTunnelManager(
    providerId: String,
    completion: @escaping (NETunnelProviderManager?, Error?) -> Void
  ) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        completion(nil, error)
        return
      }

      let staleManagers =
        managers?.filter { mgr in
          guard let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol else {
            return mgr.localizedDescription == self.packetTunnelDisplayName
          }
          return
            proto.providerBundleIdentifier == providerId
            || mgr.localizedDescription == self.packetTunnelDisplayName
        } ?? []

      self.removeTunnelManagers(staleManagers) { removeError in
        if let removeError {
          completion(nil, removeError)
          return
        }
        self.createTunnelManager(providerId: providerId, completion: completion)
      }
    }
  }

  private func removeTunnelManagers(
    _ managers: [NETunnelProviderManager],
    completion: @escaping (Error?) -> Void
  ) {
    guard !managers.isEmpty else {
      completion(nil)
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var firstError: Error?

    for manager in managers {
      group.enter()
      manager.removeFromPreferences { error in
        if let error {
          lock.lock()
          if firstError == nil {
            firstError = error
          }
          lock.unlock()
        }
        group.leave()
      }
    }

    group.notify(queue: .main) {
      completion(firstError)
    }
  }

  private func createTunnelManager(
    providerId: String,
    completion: @escaping (NETunnelProviderManager?, Error?) -> Void
  ) {
    let manager = NETunnelProviderManager()
    let proto = NETunnelProviderProtocol()
    proto.providerBundleIdentifier = providerId
    proto.serverAddress = self.packetTunnelDisplayName
    proto.providerConfiguration = [
      "options": self.storedPacketTunnelOptions() ?? [:]
    ]

    manager.protocolConfiguration = proto
    manager.localizedDescription = self.packetTunnelDisplayName
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

  private func prepareManagerWithLatestOptions(
    manager: NETunnelProviderManager,
    options: [String: NSObject],
    completion: @escaping (NETunnelProviderManager?, Error?) -> Void
  ) {
    guard let providerId = packetTunnelProviderBundleId() else {
      completion(
        nil,
        NSError(
          domain: "Xstream.PacketTunnel", code: -1,
          userInfo: [
            NSLocalizedDescriptionKey: "Missing PacketTunnel provider bundle id"
          ]))
      return
    }

    let proto =
      (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
    proto.providerBundleIdentifier = providerId
    proto.serverAddress = self.packetTunnelDisplayName
    proto.providerConfiguration = [
      "options": options
    ]

    manager.protocolConfiguration = proto
    manager.localizedDescription = self.packetTunnelDisplayName
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

  private func shouldExposeStartedAt(for state: String) -> Bool {
    switch state {
    case "connected", "connecting", "reasserting", "disconnecting":
      return true
    default:
      return false
    }
  }

  private func resolveLastDisconnectError(
    manager: NETunnelProviderManager?,
    state: String,
    completion: @escaping (String?) -> Void
  ) {
    let storedError = readLastError()?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedStoredError = storedError?.isEmpty == false ? storedError : nil
    guard let manager else {
      completion(normalizedStoredError)
      return
    }
    guard state == "disconnected" || state == "invalid" else {
      completion(normalizedStoredError)
      return
    }

    #if os(iOS) || os(macOS)
      if #available(iOS 16.0, macOS 13.0, *) {
        manager.connection.fetchLastDisconnectError { error in
          if let error {
            let described = self.describeError(error)
            self.writeLastError(described)
            completion(described)
            return
          }
          completion(normalizedStoredError)
        }
        return
      }
    #endif

    completion(normalizedStoredError)
  }

  private func startPreparedPacketTunnel(
    manager: NETunnelProviderManager,
    options: [String: NSObject],
    allowRepairOnIOS: Bool,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    do {
      clearStartedAt()
      try manager.connection.startVPNTunnel(options: options)
      clearLastError()
      emitPacketTunnelStateChanged()

      #if os(iOS)
        verifyIOSPacketTunnelStartup(
          manager: manager,
          options: options,
          allowRepair: allowRepairOnIOS,
          completion: completion
        )
      #else
        completion(.success(()))
      #endif
    } catch {
      let errorMessage = describeError(error)
      #if os(iOS)
        if allowRepairOnIOS && isPluginRegistrationError(errorMessage) {
          repairAndRestartPacketTunnel(options: options, completion: completion)
          return
        }
      #endif
      writeLastError(errorMessage)
      emitPacketTunnelError(code: "start-failed", message: errorMessage)
      completion(.failure(error))
    }
  }

  #if os(iOS)
    private func verifyIOSPacketTunnelStartup(
      manager: NETunnelProviderManager,
      options: [String: NSObject],
      allowRepair: Bool,
      completion: @escaping (Result<Void, Error>) -> Void
    ) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        let state = self.mapStatus(manager.connection.status)
        if state == "disconnected" || state == "invalid" {
          self.resolveLastDisconnectError(manager: manager, state: state) { lastError in
            if allowRepair, self.isPluginRegistrationError(lastError) {
              self.repairAndRestartPacketTunnel(options: options, completion: completion)
              return
            }
            if let lastError,
              !lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
              completion(
                .failure(
                  PigeonError(
                    code: "start-failed",
                    message: lastError,
                    details: nil
                  )
                )
              )
              return
            }
            completion(.success(()))
          }
          return
        }

        completion(.success(()))
      }
    }

    private func repairAndRestartPacketTunnel(
      options: [String: NSObject],
      completion: @escaping (Result<Void, Error>) -> Void
    ) {
      guard let providerId = packetTunnelProviderBundleId() else {
        let error = PigeonError(
          code: "manager-repair-failed",
          message: "Missing PacketTunnel provider bundle id",
          details: nil
        )
        let errorMessage = describeError(error)
        writeLastError(errorMessage)
        emitPacketTunnelError(code: "manager-repair-failed", message: errorMessage)
        completion(.failure(error))
        return
      }

      recreateTunnelManager(providerId: providerId) { manager, recreateError in
        if let recreateError {
          let errorMessage = self.describeError(recreateError)
          self.writeLastError(errorMessage)
          self.emitPacketTunnelError(code: "manager-repair-failed", message: errorMessage)
          completion(.failure(recreateError))
          return
        }

        guard let manager else {
          let error = PigeonError(
            code: "manager-repair-failed",
            message: "No available Packet Tunnel manager after repair",
            details: nil
          )
          let errorMessage = self.describeError(error)
          self.writeLastError(errorMessage)
          self.emitPacketTunnelError(code: "manager-repair-failed", message: errorMessage)
          completion(.failure(error))
          return
        }

        self.prepareManagerWithLatestOptions(manager: manager, options: options) {
          repairedManager, prepareError in
          if let prepareError {
            let errorMessage = self.describeError(prepareError)
            self.writeLastError(errorMessage)
            self.emitPacketTunnelError(code: "manager-repair-failed", message: errorMessage)
            completion(.failure(prepareError))
            return
          }

          guard let repairedManager else {
            let error = PigeonError(
              code: "manager-repair-failed",
              message: "Packet Tunnel manager was not prepared after repair",
              details: nil
            )
            let errorMessage = self.describeError(error)
            self.writeLastError(errorMessage)
            self.emitPacketTunnelError(code: "manager-repair-failed", message: errorMessage)
            completion(.failure(error))
            return
          }

          self.startPreparedPacketTunnel(
            manager: repairedManager,
            options: options,
            allowRepairOnIOS: false,
            completion: completion
          )
        }
      }
    }
  #endif

  private func describeError(_ error: Error) -> String {
    if let pigeonError = error as? PigeonError {
      var parts: [String] = []
      parts.append("code=\(pigeonError.code)")
      if let message = pigeonError.message,
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        parts.append("message=\(message)")
      }
      if let details = pigeonError.details {
        let detailString = String(describing: details).trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        if !detailString.isEmpty {
          parts.append("details=\(detailString)")
        }
      }
      return parts.joined(separator: ", ")
    }

    let nsError = error as NSError
    var parts: [String] = []
    parts.append("domain=\(nsError.domain)")
    parts.append("code=\(nsError.code)")
    let localized = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    if !localized.isEmpty {
      parts.append("message=\(localized)")
    }
    if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
      !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      parts.append("reason=\(reason)")
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      parts.append(
        "underlying=\(underlying.domain)(\(underlying.code)): \(underlying.localizedDescription)")
    }
    if (nsError.domain == "NEConfigurationErrorDomain" && nsError.code == 10)
      || (nsError.domain == "NEVPNErrorDomain" && nsError.code == 5)
    {
      parts.append("hint=Packet Tunnel extension signing/entitlements are invalid or missing")
    }
    return parts.joined(separator: ", ")
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

    getPacketTunnelStatus { result in
      guard case .success(let status) = result else {
        return
      }
      DispatchQueue.main.async {
        flutterApi.onPacketTunnelStateChanged(status: status, completion: { _ in })
      }
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
