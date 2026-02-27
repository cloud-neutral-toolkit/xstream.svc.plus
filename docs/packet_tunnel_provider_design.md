# PacketTunnelProvider Design

This document describes the design and architecture for the `PacketTunnelProvider` component used by Xstream to implement a system VPN / secure network tunnel on Apple platforms. It lives under the `Network Extension` framework and is the single entry point for all system-wide network traffic.

## Role and Responsibilities

* Act as the core of the secure tunnel implementation across iOS and macOS.
* Intercept outbound and inbound IP packets at the system level using `NEPacketTunnelProvider`.
* Forward traffic through Xray core for encryption, routing, and network acceleration.
* Handle DNS requests, configuration, and lifecycle management.

## Architectural Constraints

The PacketTunnelProvider must adhere to the global semantics and usage constraints outlined in `AGENTS.md`:

* **Only use NEPacketTunnelProvider**: This is the only permitted API for system-wide networking. No user-space TUN hacks, SOCKS forwarding, or sudo routing is allowed.
* **Consistent semantics**: Networking features are designed as a secure tunnel, avoiding any wording or implementation that implies censorship, bypass, or geo-specific behavior.
* **DNS is part of the tunnel**: DNS handling occurs within the tunnel and is never treated as a workaround.

## Interaction with Go core and Flutter

* The Flutter-side native bridge (`lib/utils/native_bridge.dart`) starts Apple Packet Tunnel mode through `DarwinHostApi`.
* `darwin/MacosHostApi.swift` implements `DarwinHostApiImpl`, which persists tunnel options, prepares `NETunnelProviderManager`, and starts or stops the tunnel connection.
* `macos/PacketTunnel/PacketTunnelProvider.swift` and `ios/PacketTunnel/PacketTunnelProvider.swift` implement the provider that applies `NEPacketTunnelNetworkSettings`, resolves the live Packet Tunnel file descriptor / `utun` handle from the extension process, and hands runtime control to `XrayTunnelBridge`.
* The Go core (`go_core/bridge_*.go`) and Xray runtime perform packet processing, routing, encryption, DNS handling, and network acceleration once the provider has started successfully.

## Lifecycle and Control

1. **Start request**: The user enables VPN / TUN mode in Flutter. `lib/utils/native_bridge.dart` writes the runtime config path into a tunnel profile and calls `DarwinHostApi.startPacketTunnel()`.
2. **Manager preparation**: `DarwinHostApiImpl` loads or creates a `NETunnelProviderManager`, refreshes `NETunnelProviderProtocol` with the latest options, saves preferences, and then calls `startVPNTunnel(options:)`.
3. **Provider startup**: `PacketTunnelProvider.startTunnel(options:completionHandler:)` runs inside the Network Extension process. The provider resolves the options map, decides IPv4/IPv6 settings, and applies `NEPacketTunnelNetworkSettings`.
4. **Engine handoff**: After network settings are active, the provider resolves an accessible Packet Tunnel file descriptor from `packetFlow` or the extension's open `utun` descriptors, sanitizes the Darwin TUN inbound config, and calls `XrayTunnelBridge.start(configData:fd:fdDetail:egressInterface:)`.
5. **Runtime operation**: The Go / Xray runtime owns packet forwarding, DNS inside the secure tunnel, and engine lifecycle. The provider remains responsible for Network Extension state and teardown.
6. **Stop**: When the user disables the tunnel or startup fails, `stopTunnel(with:completionHandler:)` or the local rollback path stops the engine, clears active state, and updates shared status.

The provider does not keep a second "start without Packet Tunnel fd" path. If the Network Extension process cannot hand off a valid system tunnel fd to Xray, startup fails and reports the handoff error instead of attempting an alternate engine bootstrap.

This means Apple startup failures can occur in multiple layers:
- Flutter or profile generation
- `DarwinHostApiImpl` / `NETunnelProviderManager`
- macOS authorization for the System VPN / Packet Tunnel
- `PacketTunnelProvider.startTunnel`
- `XrayTunnelBridge` / Go runtime initialization

They should not all be treated as the same category of failure.

## Error Handling and Recovery

* `DarwinHostApiImpl` persists the latest startup error to the shared app-group defaults so Flutter can query and present actionable guidance.
* Packet Tunnel provider failures are logged with the `plus.svc.xstream` subsystem and mirrored into the shared status store when startup or rollback fails.
* The current macOS UI now checks for authorization-related failures such as `permission denied` and opens a permissions guide that directs the user to approve the System VPN / Packet Tunnel request for `Xstream Secure Tunnel`.
* Restart and recovery behavior is currently conservative: the tunnel is stopped on startup failure and the user is expected to retry after fixing authorization, signing, configuration, or runtime issues.
* Missing or invalid Packet Tunnel fd handoff is treated as a provider startup failure, because Packet Tunnel is the only permitted system-level entry point on Apple platforms.

## Testing and Validation

* Unit tests for Go core packet handling exist in `libXray/xray_wrapper_test.go` and `go_core` packages.
* Apple `RunnerTests` targets are currently placeholders; there is not yet automated Packet Tunnel startup coverage for manager preparation, authorization flow, or provider startup.
* Current Apple validation is primarily manual. Use [docs/macos-menubar-regression-checklist.md](/Users/shenlan/workspaces/cloud-neutral-toolkit/xstream.svc.plus/docs/macos-menubar-regression-checklist.md) together with Packet Tunnel system logs during development.
* During development, verify Packet Tunnel startup using `xcodebuild` or `flutter run`, then inspect `/usr/bin/log show` entries for the `plus.svc.xstream` subsystem and `PacketTunnel` process.

## Documentation and Maintenance

* Any changes to the packet tunnel configuration format should be reflected in `docs/VpnConfigStruct.md` and this document.
* Future enhancements must not violate App Store objective or global semantics: maintain compliance for macOS App Store target.

---

This design document provides the high‑level overview of how the PacketTunnelProvider integrates into Xstream. For detailed implementation, refer to platform source files under `darwin/` and the Go core bridge sources.

See also the cross-platform architecture diagram and extension notes: [docs/architecture_overview.md](docs/architecture_overview.md).

## Repository mapping — concrete implementation locations

The following lists where the packet-tunnel related adapters, bridge code, and platform helpers live in this repository. Use these references when implementing or reviewing platform-specific behavior.

- Apple (macOS / iOS):
	- Packet tunnel providers: `ios/PacketTunnel/PacketTunnelProvider.swift`, `macos/PacketTunnel/PacketTunnelProvider.swift` — NEPacketTunnelProvider subclasses used as the system-level entry point.
	- Host API and Pigeon bridge: `darwin/MacosHostApi.swift` — implements `DarwinHostApi` used by Flutter via Pigeon. Key methods: `savePacketTunnelProfile`, `startPacketTunnel`, `stopPacketTunnel`, `getPacketTunnelStatus`.
	- Generated Pigeon bindings: `darwin/Messages.g.swift` and files under `bindings/` (check `lib/bindings/`) used for typed host/Flutter APIs.

- Native bridge (cross-platform Flutter-side):
	- `lib/utils/native_bridge.dart` — central routing for Packet Tunnel lifecycle from Flutter; shows per-platform control flow (FFI vs MethodChannel vs Pigeon). See `startNodeForTunnel`, `stopNodeForTunnel`, `startPacketTunnel`, `stopPacketTunnel`.

- Go core adapters and platform bridges:
	- `go_core/bridge_ios.go`, `go_core/bridge_android.go`, `go_core/bridge_linux.go`, `go_core/bridge_windows.go`, `go_core/bridge.go` — platform-specific entry points that connect the host platform to the Go packet processing and Xray integration.
	- For Apple platforms, the current implementation hands an fd hint from the provider into `XrayTunnelBridge`; it does not currently document a direct `packetFlow.readPackets(...)` / `writePackets(...)` loop in the provider.

- Android:
	- VPN service and controller: `android/app/src/main/kotlin/.../XstreamPacketTunnelService.kt`, `android/app/src/main/kotlin/.../PacketTunnelController.kt` — `VpnService` implementation and TUN fd handling.
	- Manifest registration: `android/app/src/main/AndroidManifest.xml` includes `android.net.VpnService` action.
	- The Go bridge supports `StartXrayTunnelWithFd` use-cases in `go_core/bridge_android.go`.

- Linux and Windows:
	- TUN / tun2socks flow: `go_core/bridge_linux.go`, `go_core/bridge_windows.go` and `libXray/` wrappers describe how TUN inbound is handed to xray-core or tun2socks.
	- Flutter-side FFI calls in `lib/utils/native_bridge.dart` call `startXray(configJson)` on these platforms when running TUN mode.

- Vendor / core implementation references:
	- `vendor/Xray-core/` and `libXray/` contain the lower-level tun adapters and integration notes (see `vendor/Xray-core/proxy/tun/README.md` for platform fd handling).

Notes:
- When updating or extending platform behavior, keep adapters thin: prefer adding behavior in `go_core/*` or `libXray/` so the Flutter API surface (`lib/utils/native_bridge.dart`) remains stable.
- For Apple platforms, do not replace `NEPacketTunnelProvider` with user-space TUN hacks; all platform code must use `NEPacketTunnelProvider` (see `AGENTS.md`).

## TODO / features

- Add automated Apple-side tests for:
  - `DarwinHostApiImpl` manager preparation
  - Packet Tunnel startup success and failure cases
  - authorization-denied detection and user guidance
- Add startup-stage reporting so Flutter can distinguish:
  - manager load / save failures
  - authorization failures
  - provider startup failures
  - Go / Xray runtime failures
- Add a stable, documented diagnostic workflow for Packet Tunnel logs and shared app-group status keys.
