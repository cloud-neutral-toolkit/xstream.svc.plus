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

* The native bridge (`lib/utils/native_bridge.dart`) communicates with platform code to start and stop the tunnel, and to update configuration.
* Platform-specific code (Swift/Objective-C on Apple platforms) initializes an `NEPacketTunnelProvider` subclass and passes configuration to the Go core via the PacketTunnel bridge (`go_core/*`).
* The Go core (`go_core/bridge_*.go`) implements packet processing logic, which may call into `xray-core` as a static or dynamic library. Packets are encrypted, multiplexed, and forwarded through remote servers.

## Lifecycle and Control

1. **Start**: The user enables the VPN. Flutter UI sends command to native bridge.
2. **Configuration**: A VPN configuration JSON is generated from templates (`lib/templates/`) and passed to the packet tunnel provider. The config includes server list, routing rules, DNS settings, and acceleration parameters.
3. **Initialization**: `NEPacketTunnelProvider.startTunnel(options:completionHandler:)` is invoked. The provider sets up `NWTCPConnection`, `NWUDPSession`, and hooks into network stack using `packetFlow`.
4. **Packet Handling**: Incoming/outgoing packets are read from `packetFlow` and dispatched to Go core via FFI. Processed packets are written back to `packetFlow`.
5. **DNS**: DNS queries are intercepted and resolved through the tunnel or through user-configured servers. Response packets are injected back into `packetFlow`.
6. **Stop**: When user disables VPN or an error occurs, `stopTunnel(with:reason:completionHandler:)` is executed, cleaning resources and notifying Flutter.

## Error Handling and Recovery

* Non-fatal errors are logged via `app_logger` and surfaced to Flutter through the native bridge.
* If the packet tunnel provider fails to establish or maintain connection (e.g., network changed), it may automatically attempt to restart by calling `expireTunnelWithError(_:)` or using `setTunnelNetworkSettings(_:completionHandler:)`.
* The Go core reports health states and metrics that can trigger reconfiguration or connection resets.

## Testing and Validation

* Unit tests for Go core packet handling exist in `libXray/xray_wrapper_test.go` and `go_core` packages.
* Integration tests on Apple platforms include launching the VPN in simulator and verifying `packetFlow` data counts, DNS resolution, and traffic forwarding. See `docs/macos-menubar-regression-checklist.md` for macOS-specific checks.
* During development, use `xcodebuild` and `flutter run` with packet tunnel logs enabled.

## Documentation and Maintenance

* Any changes to the packet tunnel configuration format should be reflected in `docs/VpnConfigStruct.md` and this document.
* Future enhancements must not violate App Store objective or global semantics: maintain compliance for macOS App Store target.

---

This design document provides the high‑level overview of how the PacketTunnelProvider integrates into Xstream. For detailed implementation, refer to platform source files under `darwin/` and the Go core bridge sources.
