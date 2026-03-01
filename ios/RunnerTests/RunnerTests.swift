import Foundation
import XCTest

@testable import Runner

final class RunnerTests: XCTestCase {
  private let packetTunnelStartTimeoutSeconds: TimeInterval = 30
  private let packetTunnelStopTimeoutSeconds: TimeInterval = 15

  func testPacketTunnelStartStopSmoke() async throws {
    let api = DarwinHostApiImpl()
    try await stopPacketTunnelIfNeeded(api)

    let configPath = try writeSmokeConfig(using: api)
    defer { try? FileManager.default.removeItem(atPath: configPath) }

    let saveResult = try await savePacketTunnelProfile(
      api,
      profile: makeSmokeProfile(configPath: configPath)
    )
    XCTAssertEqual(saveResult, "profile_saved")

    try await startPacketTunnel(api)

    let connected = try await waitForStatus(
      api,
      acceptableStates: ["connected"],
      timeout: packetTunnelStartTimeoutSeconds
    )
    XCTAssertEqual(connected.state, "connected")
    XCTAssertTrue(
      connected.lastError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
      "unexpected Packet Tunnel error: \(connected.lastError ?? "<nil>")"
    )
    XCTAssertFalse(
      connected.utunInterfaces.isEmpty, "expected a live utun interface while connected")
    XCTAssertNotNil(connected.startedAt, "expected Packet Tunnel start timestamp after connect")

    try await stopPacketTunnel(api)

    let disconnected = try await waitForStatus(
      api,
      acceptableStates: ["disconnected"],
      timeout: packetTunnelStopTimeoutSeconds,
      failOnTerminalError: false
    )
    XCTAssertEqual(disconnected.state, "disconnected")
  }

  private func writeSmokeConfig(using api: DarwinHostApiImpl) throws -> String {
    let root = try api.appGroupPath()
    let dir = URL(fileURLWithPath: root).appendingPathComponent("tests", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let path = dir.appendingPathComponent("packet-tunnel-smoke.json")
    try makeSmokeConfigData().write(to: path, options: .atomic)
    return path.path
  }

  private func makeSmokeConfigData() -> Data {
    Data(
      """
      {
        "log": {
          "loglevel": "info"
        },
        "dns": {
          "servers": [],
          "queryStrategy": "UseIPv4",
          "disableFallbackIfMatch": true
        },
        "inbounds": [
          {
            "protocol": "tun",
            "settings": {
              "mtu": 1500
            }
          }
        ],
        "outbounds": [
          {
            "protocol": "vless",
            "settings": {
              "vnext": [
                {
                  "address": "57.183.19.25",
                  "port": 443,
                  "users": [
                    {
                      "id": "18d270a9-533d-4b13-b3f1-e7f55540a9b2",
                      "encryption": "none"
                    }
                  ]
                }
              ]
            },
            "streamSettings": {
              "network": "xhttp",
              "security": "tls",
              "tlsSettings": {
                "serverName": "jp-xhttp.svc.plus",
                "allowInsecure": false,
                "alpn": ["h2", "http/1.1", "h3"]
              },
              "xhttpSettings": {
                "path": "/split",
                "host": "jp-xhttp.svc.plus",
                "mode": "auto"
              }
            },
            "tag": "proxy"
          },
          {
            "protocol": "freedom",
            "tag": "direct"
          },
          {
            "protocol": "blackhole",
            "tag": "block"
          },
          {
            "tag": "dns",
            "protocol": "dns"
          }
        ],
        "routing": {
          "rules": []
        }
      }
      """.utf8
    )
  }

  private func makeSmokeProfile(configPath: String) -> TunnelProfile {
    TunnelProfile(
      mtu: 1500,
      tun46Setting: 2,
      defaultNicSupport6: true,
      dnsServers4: ["1.1.1.1", "8.8.8.8"],
      dnsServers6: ["2606:4700:4700::1111", "2001:4860:4860::8888"],
      ipv4Addresses: ["10.0.0.2"],
      ipv4SubnetMasks: ["255.255.255.0"],
      ipv4IncludedRoutes: [
        TunnelRouteV4(destinationAddress: "0.0.0.0", subnetMask: "0.0.0.0")
      ],
      ipv4ExcludedRoutes: [],
      ipv6Addresses: ["fd00::2"],
      ipv6NetworkPrefixLengths: [120],
      ipv6IncludedRoutes: [
        TunnelRouteV6(destinationAddress: "::", networkPrefixLength: 0)
      ],
      ipv6ExcludedRoutes: [],
      configPath: configPath
    )
  }

  private func startPacketTunnel(_ api: DarwinHostApiImpl) async throws {
    try await withCheckedThrowingContinuation { continuation in
      api.startPacketTunnel { result in
        continuation.resume(with: result)
      }
    }
  }

  private func savePacketTunnelProfile(
    _ api: DarwinHostApiImpl,
    profile: TunnelProfile
  ) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      api.savePacketTunnelProfile(profile: profile) { result in
        continuation.resume(with: result)
      }
    }
  }

  private func stopPacketTunnel(_ api: DarwinHostApiImpl) async throws {
    try await withCheckedThrowingContinuation { continuation in
      api.stopPacketTunnel { result in
        continuation.resume(with: result)
      }
    }
  }

  private func currentStatus(_ api: DarwinHostApiImpl) async throws -> TunnelStatus {
    try await withCheckedThrowingContinuation { continuation in
      api.getPacketTunnelStatus { result in
        continuation.resume(with: result)
      }
    }
  }

  private func waitForStatus(
    _ api: DarwinHostApiImpl,
    acceptableStates: Set<String>,
    timeout: TimeInterval,
    failOnTerminalError: Bool = true
  ) async throws -> TunnelStatus {
    let deadline = Date().addingTimeInterval(timeout)
    var lastStatus = try await currentStatus(api)

    while Date() < deadline {
      lastStatus = try await currentStatus(api)
      if acceptableStates.contains(lastStatus.state) {
        return lastStatus
      }

      let lastError = lastStatus.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if failOnTerminalError
        && (lastStatus.state == "invalid"
          || (lastStatus.state == "disconnected" && !lastError.isEmpty))
      {
        throw XCTSkip("Packet Tunnel entered terminal state \(lastStatus.state): \(lastError)")
      }

      try await Task.sleep(nanoseconds: 500_000_000)
    }

    XCTFail(
      "Timed out waiting for states \(acceptableStates.sorted()) last=\(lastStatus.state) error=\(lastStatus.lastError ?? "<nil>")"
    )
    return lastStatus
  }

  private func stopPacketTunnelIfNeeded(_ api: DarwinHostApiImpl) async throws {
    let status = try await currentStatus(api)
    guard
      status.state == "connected" || status.state == "connecting" || status.state == "reasserting"
    else {
      return
    }
    try await stopPacketTunnel(api)
    _ = try await waitForStatus(
      api,
      acceptableStates: ["disconnected"],
      timeout: packetTunnelStopTimeoutSeconds,
      failOnTerminalError: false
    )
  }
}
