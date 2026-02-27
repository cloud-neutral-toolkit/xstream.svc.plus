# iOS Packet Tunnel Real-Device Follow-up

Last updated: 2026-02-27

## Current Status

- iOS release install to physical device passed on UDID `00008140-000E75903EF2801C`.
- Repo-local iPhone smoke skill was added under `skills/xstream-ios-real-device-smoke/`.
- Device smoke script passed for build, install, relaunch, process visibility, and sandbox readiness.
- `RunnerTests.testPacketTunnelStartStopSmoke()` now compiles and launches on device, but Packet Tunnel control-plane start is still blocked at runtime by system permission denial.

## Verified Today

- `make ios-install-release IOS_DEVICE=00008140-000E75903EF2801C`
- `skills/xstream-ios-real-device-smoke/scripts/ios_real_device_smoke.sh --device 00008140-000E75903EF2801C --report skills/xstream-ios-real-device-smoke/last-report.md --keep-artifacts`
- `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'id=00008140-000E75903EF2801C' -only-testing:RunnerTests/RunnerTests/testPacketTunnelStartStopSmoke`

## Current Blocker

The real-device Packet Tunnel smoke test reaches the native start path but fails when the system loads or starts the Network Extension configuration:

```text
Failed to load configurations: Error Domain=NEConfigurationErrorDomain Code=10 "permission denied"
Error Domain=NEVPNErrorDomain Code=5 "permission denied"
```

This is a runtime environment / signing / entitlement / provisioning blocker, not the current XCTest implementation.

## Changes Added For This Work

- iOS/macOS Packet Tunnel provider now uses iPhoneOS-safe fallback values for `SYSPROTO_CONTROL` and `UTUN_OPT_IFNAME`.
- `RunnerTests` gained a Packet Tunnel start/stop smoke test that writes a temporary tunnel profile and configuration into the App Group container.
- `RunnerTests` signing was configured for the existing Apple development team.
- `Runner` test host now skips Flutter startup when launched under `XCTest`, so native Packet Tunnel control-plane tests can run without depending on Flutter debug bootstrapping.
- `Runner-Bridging-Header.h` no longer imports a redundant unresolved `bridge.h`.

## Next Session Checklist

1. Re-run the same `xcodebuild test` command with the iPhone unlocked before test startup.
2. Inspect Xcode signing for `Runner`, `PacketTunnel`, and `RunnerTests` on the same Apple team and confirm the active provisioning profiles on the physical device.
3. Re-check `Network Extension` and `App Groups` entitlements on both `Runner` and `PacketTunnel`.
4. Confirm the device trusts the current developer signing identity and that no stale Packet Tunnel configuration remains in system preferences.
5. If permission denial persists, collect the matching Xcode test result bundle and device-side Network Extension logs for `NEConfigurationErrorDomain` / `NEVPNErrorDomain`.
6. After permission is resolved, re-run `RunnerTests.testPacketTunnelStartStopSmoke()` and then extend the smoke pass to cover UI-triggered connect/disconnect.

## Useful Paths

- Skill: `skills/xstream-ios-real-device-smoke/`
- Latest smoke report: `skills/xstream-ios-real-device-smoke/last-report.md`
- Latest failed device test result bundle:
  `/Users/shenlan/Library/Developer/Xcode/DerivedData/Runner-dxfoinntfllvvedximfyrhzjuztu/Logs/Test/Test-Runner-2026.02.27_19-26-33-+0800.xcresult`
