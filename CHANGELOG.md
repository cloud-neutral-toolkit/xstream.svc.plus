# Unreleased

## ✅ Changes
- Fixed iOS Packet Tunnel provider build by replacing unavailable iPhoneOS SDK `utun` macros with stable Darwin fallback constants
- Added repo-local `xstream-ios-real-device-smoke` skill with executable iPhone smoke script, baseline, test cases, and latest report
- Added iOS `RunnerTests` Packet Tunnel start/stop smoke coverage and test-host fixes for real-device execution
- Recorded current iPhone Packet Tunnel smoke blocker and next-step checklist in `docs/ios-packet-tunnel-real-device-followup.md`
- Removed tun2socks-based system-wide path; Packet Tunnel is now the only TUN/VPN entry on macOS
- Cleaned tun2socks scripts/resources/docs and related native/Dart APIs
- Added iOS/macOS `PacketTunnel` app extension targets with embedded `.appex` wiring in both Xcode projects
- Added Darwin Pigeon channel (`pigeons/darwin.dart`) and generated bridge code for Flutter and Swift
- Added `DarwinHostApiImpl` native implementation and startup registration in iOS/macOS app entry points
- Migrated Packet Tunnel provider implementation pattern to options-driven network settings on iOS/macOS
- Unified Darwin Packet Tunnel control to Pigeon single entry and removed Runner `NativeBridge+PacketTunnel` legacy channel wiring
- Added xray tunnel bridge symbols (`StartXrayTunnel`, `SubmitInboundPacket`, `StopXrayTunnel`, `FreeXrayTunnel`) in Go/C bridge layer
- Added Android Packet Tunnel native bridge (`StartXrayTunnelWithFd`) and connected `VpnService` TUN fd to xray-core tun inbound session
- Added Android JNI tunnel adapter (`packet_tunnel_jni`) and wired Packet Tunnel lifecycle to native xray tunnel start/stop
- Upgraded `go_core` xray dependency to xray-core `v1.260206.0` for native tun inbound support on mobile Packet Tunnel path
- Added Packet Tunnel startup rollback path in iOS/macOS providers and documented startup/failure sequence in `docs/system-vpn-packet-tunnel-xray26.md`
- Added client-side `vless://` URI support for node import and outbound generation, including `tcp` and `xhttp` transport parameters

# XStream v0.2.0 - Windows Release

_Release Date: 2025-06-10_

## ✨ Features
- Windows platform support with service-based deployment
- Packaging includes automatic service registration for background running
- Integrated Bridge Windows module for one-click start and recovery

## ✅ Changes
- Verified config.json and Task Scheduler deployment
- Passed multi-region switch and proxy tests on Windows

# XStream v0.1.4 - macOS Tray Support

_Release Date: 2025-06-09_

## ✨ Features
- macOS system tray status icon with window toggle
- Icon generation script for automated build

## ✅ Changes
- Improved minimize behavior on macOS
- Cleaned plugin registration

# XStream v0.1.3 - Linux Runner

_Release Date: 2025-06-08_

## ✨ Features
- Go-based Linux native bridge with systemd support
- Updated CI workflow for Linux builds

## ✅ Changes
- Fixed cross-platform build scripts
- Added Linux systemd documentation

# XStream v0.1.2 - Beta Update

_Release Date: 2025-06-08_

## ✨ Features
- Static `index.json` based update check
- Modular update system with persistent settings
- Injects build metadata into About dialog
- Xray config generation via Dart templates
- Inlined reset script for macOS reliability
- Revised license attributions

## ✅ Changes
- Fixed duplicate network service start
- Resolved logConsoleKey import
- Improved CI and BuildContext usage

# XStream v0.1.1 - Minor Improvements

_Release Date: 2025-06-07_

## ✨ Features
- "Reset All Configuration" option in settings
- Updated icons and asset handling without Git LFS

## ✅ Changes
- Fixed macOS reset script quoting issues
- Updated Windows app icon generation



# XStream v0.1.0 - First Public Preview

_Release Date: 2025-06-06_

## ✨ Features

- 🎯 **Cross-platform network acceleration engine powered by XTLS / VLESS**
- 💻 macOS native integration via Swift + LaunchAgent + Xray
- 🛠️ Integrated `xray` binaries for both `arm64` and `x86_64` architectures
- 📂 Per-user config persistence in `ApplicationSupport` directory
- 📡 Built-in Flutter UI for node selection and management
- 📤 One-click sync to write config and generate launchd service

## ✅ Changes

- Migrated `xray` binaries into `macos/Resources/xray/` (unified resource location)
- Implemented Swift-side logic to:
  - Detect platform architecture (`arm64` / `x86_64`)
  - Copy correct binary into `/opt/homebrew/bin/xray`
  - Set execution permissions
- Added `url_launcher` plugin support with macOS integration (`url_launcher_macos`)
- Simplified `project.pbxproj` to remove unused `inputPaths` / `outputPaths`
- Removed old `macos/xray/` location and binaries

## 🔧 Dev & Build

- Updated `Makefile` to support both `arm64` and `x86_64` macOS targets
- Rebuilt `Podfile.lock` to include new plugins (`url_launcher_macos`)
- Optimized Swift AppleScript command formatting for stability and shell-escaping
- Code cleanup and refactor in `NativeBridge+XrayInit.swift`

## 🧪 Known Limitations

- Current version supports only **basic node config** – advanced Xray routing not yet exposed
- No system tray or background daemon control UI yet
- Tested only on macOS 12+ (Apple Silicon and Intel)

## 🔜 Roadmap

- [ ] GUI for custom route / rule editing
- [ ] Windows and Linux GUI support
- [ ] Built-in diagnostics and log viewer
