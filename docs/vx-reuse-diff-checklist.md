# VX -> Xstream Reuse Diff Checklist

## Scope
- Source baseline: `/Users/shenlan/workspaces/Xstream/VX`
- Target repo: `/Users/shenlan/workspaces/cloud-neutral-toolkit/Xstream`
- Focus areas:
  - `PacketTunnelProvider` implementation pattern
  - Darwin Pigeon native communication
  - iOS/macOS Xcode target organization

## 1) Packet Tunnel Engine Pattern

### VX baseline
- `ios/PacketTunnel/PacketTunnelProvider.swift` and `macos/PacketTunnel/PacketTunnelProvider.swift` use direct `X_darwinNew(...)` and `Tm` runtime binding.
- Provider handles packet I/O and lifecycle in a monolithic class.

### Xstream current
- `ios/PacketTunnel/PacketTunnelProvider.swift` and `macos/PacketTunnel/PacketTunnelProvider.swift` already use:
  - `SecureTunnelEngine` abstraction
  - `XrayTunnelEngine` adapter
  - `NEPacketFlowAdapter` loop abstraction
  - startup rollback path (`rollbackStartFailure`)
- Status persistence and lifecycle reporting are integrated.

### Reuse status
- `DONE`: VX PacketTunnelProvider architecture pattern has been migrated and adapted to Xstream xray-core tunnel lifecycle.
- `DONE`: Startup failure rollback path is present.
- `KEEP DIFFERENCE`: Xstream keeps Packet Tunnel as sole system-level network entry point and does not use VX-style direct `Tm` runtime start path.

## 2) Darwin Pigeon Channel

### VX baseline
- `pigeons/darwin.dart` provides legacy Darwin API:
  - `appGroupPath`
  - `startXApiServer`
  - `redirectStdErr`
  - `generateTls`
  - `setupShutdownNotification`
- Channel namespace is `dev.flutter.pigeon.vx.*`.

### Xstream current
- `pigeons/darwin.dart`, `darwin/Messages.g.swift`, `lib/app/darwin_host_api.g.dart` are present.
- Xstream channel namespace is `dev.flutter.pigeon.xstream.*`.
- Added Packet Tunnel control APIs:
  - `savePacketTunnelProfile`
  - `startPacketTunnel`
  - `stopPacketTunnel`
  - `getPacketTunnelStatus`
- Native implementation in `darwin/MacosHostApi.swift` is wired in:
  - `ios/Runner/AppDelegate.swift`
  - `macos/Runner/MainFlutterWindow.swift`

### Reuse status
- `DONE`: VX Darwin Pigeon channel model reused.
- `DONE`: Extended to one unified Packet Tunnel control path for Xstream.
- `KEEP DIFFERENCE`: `startXApiServer/generateTls` are kept as compatibility stubs in Xstream and are not used as the primary Packet Tunnel control path.

## 3) Xcode Target Organization (iOS/macOS)

### VX baseline
- iOS has `Runner + PacketTunnel` with embedded `PacketTunnel.appex`.
- macOS includes `PacketTunnel.appex`; VX also has `SystemExtension` target in the project.

### Xstream current
- iOS workspace schemes include `PacketTunnel` and `Runner`.
- macOS workspace schemes include `PacketTunnel` and `Runner`.
- Both projects embed `PacketTunnel.appex` in `Runner`.

### Reuse status
- `DONE`: VX PacketTunnel target embedding pattern reused on iOS/macOS.
- `KEEP DIFFERENCE (Intentional)`: Xstream does not import VX `SystemExtension` target; Packet Tunnel remains the sole system-level networking entry.

## 4) Workspace Sync Result (Xstream_flutter_workspace -> Xstream)

### Synced
- Core source and project changes were synced back into `/Users/shenlan/workspaces/cloud-neutral-toolkit/Xstream`.
- Includes Dart/Swift/Go/Xcode project updates already staged in `Xstream`.

### Remaining unsynced (environment-generated)
- Only root-owned/generated ephemeral files still differ under:
  - `macos/Flutter/ephemeral/*`
- These files are build-generated and not part of reusable source logic.

## 5) Next Optional Follow-ups
- Add a small regression test set for:
  - Darwin Pigeon `start/stop/status` calls
  - Packet Tunnel profile serialization consistency
- Normalize generated Flutter xcfilelist handling to avoid local root-owned ephemeral drift.

## 6) Android Secure Tunnel Data Plane

### VX baseline
- Android side in VX uses external AAR runtime (`tm_android/x.aar`) to host native tunnel/Xray logic.
- Direct Kotlin source in VX does not contain an in-repo `VpnService -> tun fd -> xray tun` bridge implementation.

### Xstream current
- Added Android `VpnService` implementation:
  - `android/app/src/main/kotlin/com/example/xstream/XstreamPacketTunnelService.kt`
- Added JNI adapter and native loader:
  - `android/app/src/main/kotlin/com/example/xstream/NativePacketTunnelBridge.kt`
  - `android/app/src/main/cpp/packet_tunnel_jni.cpp`
  - `android/app/src/main/cpp/CMakeLists.txt`
- Added Go bridge entry:
  - `go_core/bridge_android.go` exports `StartXrayTunnelWithFd(config, tunFd)`
- Added Android build wiring:
  - `android/app/build.gradle` enables `externalNativeBuild.cmake`
  - `build_scripts/build_android_xray.sh` host tag detection now supports Apple Silicon/Linux arm64
- Mobile tunnel profile now passes `configPath` into Android Packet Tunnel startup:
  - `lib/utils/native_bridge.dart`

### Reuse status
- `DONE`: Android native tunnel entry and Flutter bridge skeleton are in place in Xstream.
- `DONE`: Android data plane is wired to xray-core 26 tun inbound through `xray.tun.fd`.
- `KEEP DIFFERENCE`: VX external AAR runtime is not imported; Xstream keeps all Packet Tunnel control and native bridge code in-repo for auditability and maintainability.
