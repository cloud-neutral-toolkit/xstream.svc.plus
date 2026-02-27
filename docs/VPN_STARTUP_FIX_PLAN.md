# Phase 1: Root Cause Analysis & Planning
- [x] Analyze Flutter layer (`native_bridge.dart`, `home_screen.dart`, `main.dart`, `vpn_config_service.dart`)
- [x] Analyze Native layer (`AppDelegate.swift`, `PacketTunnelProvider.swift`, `NativeBridge+ServiceControl.swift`)
- [x] Analyze Go layer (`bridge_ios.go`, `bridge.h`)
- [x] Analyze Pigeon API (`darwin_host_api.g.dart`)
- [x] Analyze entitlements (macOS + iOS)
- [x] Identify root cause of "节点配置文件不存在" error
- [x] Write implementation plan

# Phase 2: Fix Startup Flow
- [x] Fix `_toggleNode()` in `home_screen.dart` to route based on connection mode
- [x] Fix config resolution in `native_bridge.dart` — ensure `startNodeService` passes `configPath` to native
- [x] Ensure `startPacketTunnel` resolves config, reads file content, and passes as Data to NE
- [x] Add proper error messages with diagnostic details

# Phase 3: Dual-Mode UI Integration
- [x] Wire `GlobalState.connectionMode` into `_toggleNode()` so user choice (TUN vs Proxy) controls startup path
- [x] Ensure mode toggle in Settings correctly persists and applies on next connect
- [x] Update status display to reflect correct mode

# Phase 4: Xray Config Generation (VLESS + XHTTP + XTLS)
- [ ] Verify `_generateXrayJsonConfig` produces correct config for xtls-rprx-vision
- [ ] Ensure XHTTP mode generates proper xhttpSettings
- [ ] Ensure TUN inbound config is only added when TUN mode is active
- [ ] Validate proxy-only inbound config (SOCKS + HTTP) for proxy mode

# Phase 5: Enhanced Logging & Error Handling
- [x] Add structured logging to `PacketTunnelProvider.swift`
- [x] Surface tunnel engine errors to Flutter via `onPacketTunnelError`
- [x] Add diagnostic error messages in `native_bridge.dart`

# Phase 6: iOS parity
- [ ] Add `com.apple.security.application-groups` to iOS `PacketTunnel.entitlements`
- [ ] Verify iOS `PacketTunnelProvider.swift` matches macOS implementation

# Phase 7: Verification
- [ ] Build macOS app and verify TUN mode start/stop
- [ ] Build macOS app and verify Proxy mode start/stop
- [ ] Verify mode switching during active connection
- [ ] Manual test: import VLESS URI → select node → start in both modes
