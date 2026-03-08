---
name: xstream-dev-constraints
description: Use this skill before writing or reviewing any Flutter/Dart, Go FFI, or build-script code in the Xstream repo. It enforces non-negotiable product semantics, architecture rules, coding conventions, and App Store compliance constraints that apply to every change in this project. Always read this before suggesting API designs, UI copy, or implementation approaches.
---

# Xstream Development Constraints

Authoritative constraint set for every code change in this repository.
Read **before** implementing, reviewing, or suggesting any code, UI copy, or documentation.

---

## 1. Product Semantics (Non-negotiable)

Xstream is a **legal System VPN / Secure Network Tunnel** for macOS App Store distribution.

### 1.1 Approved Vocabulary

Use **only** these terms in UI copy, docs, code comments, and variable names:

| ✅ Use | ❌ Never use |
|--------|-------------|
| Secure Tunnel | bypass / circumvent / break through |
| System VPN | any country or region name |
| Packet Tunnel | censorship / blocking / restriction |
| Encrypted Network | proxy (as a primary feature term) |
| Network Acceleration | VPN workaround / alternative path |
| Network Reliability | — |
| Privacy Protection | — |
| System-level Networking | — |

### 1.2 Architecture Constraints

- System-wide networking **must only** use **NEPacketTunnelProvider (Packet Tunnel)**.
- DNS (including DoT) is treated as **part of the secure tunnel** — never a workaround.
- **Prohibited**: user-space TUN hacks, TUN + SOCKS forwarding, sudo routing, proxy env vars.

---

## 2. Flutter / Dart Coding Rules

### 2.1 State Management
- Global state lives in `lib/utils/global_config.dart` (`GlobalState`, `ValueNotifier`).
- **Never** manipulate service objects directly from the view layer.
- Use `ValueListenableBuilder` to react to state changes.

### 2.2 Localization
- **All** UI-facing strings must use `context.l10n.get('key')`.
- Adding a new key? Add both `en` and `zh` translations in `lib/l10n/app_localizations.dart` in the same commit.
- Never hardcode Chinese or English text in widget code.

### 2.3 Logging
- Use `addAppLog(...)` for application-level logs.
- **Never** use `print(...)` in production code paths.
- No sensitive data (passwords, tokens, UUIDs) in logs.

### 2.4 Async & Error Handling
- Always `await` async calls and wrap in `try/catch`.
- Surface errors to the user via `SnackBar` or `Dialog` — never swallow silently.

### 2.5 Screen / AppBar Embedding Rule
- Screens embedded inside `MainPage` (`IndexedStack`) **must not** render their own `AppBar`.
  - The outer `MainPage` provides the breadcrumb AppBar for all embedded pages.
- Screens that can be pushed via `Navigator.push` independently **must** render their own `AppBar`.
- Use a constructor parameter (e.g. `breadcrumbItems`) to distinguish the two cases.

### 2.6 Native Interaction
- Prefer service-layer methods (`VpnConfigService`, `NativeBridge`) over raw FFI in view code.
- Do **not** handle file paths, permissions, or FFI details in screen widgets.

### 2.7 Lint & Format
- All Dart changes must pass `flutter analyze` with zero new issues.
- Format with `dart format .` before committing.
- Local `// ignore` suppressions must include a reason comment.

---

## 3. Go FFI Rules

- Every exported function must return a result string or an explicit error code — never panics.
- Pointers created via `C.CString` / `C.malloc` must have a corresponding `FreeCString` (Go side). The Flutter caller **must** free after use.
- Platform-specific logic → `bridge_<platform>.go`. Shared exported functions → `bridge.go` only.
- macOS system networking is handled by the Swift `PacketTunnel` extension, **not** Go code.

---

## 4. Build & Version Rules

### 4.1 Version Source of Truth
- Version is defined **only** in `pubspec.yaml` (format: `MAJOR.MINOR.PATCH+BUILD`).
- Before an Xcode Archive, run:
  ```
  make sync-macos-config
  ```
  This regenerates `macos/Flutter/ephemeral/Flutter-Generated.xcconfig` so Xcode picks up the correct `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.

### 4.2 Makefile Targets (canonical names)

| Goal | Command |
|------|---------|
| macOS ARM64 release + DMG | `make build-macos-arm64` |
| macOS x64 release + DMG | `make build-macos-x64` |
| Sync Xcode config | `make sync-macos-config` |
| iOS release IPA | `make build-ios-ipa` |
| Windows x64 | `make build-windows-x64` |
| Linux x64 | `make build-linux-x64` |
| Clean | `make clean` |

### 4.3 PR Checklist
- [ ] `flutter analyze` passes (zero issues)
- [ ] `dart format .` applied
- [ ] `CHANGELOG.md` updated if user-facing change
- [ ] Build target tested and noted in PR description

---

## 5. Resources & Templates

- New static assets → `assets/` + register in `pubspec.yaml`.
- Modifying `lib/templates/` → sync `services/vpn_config_service.dart` in the same commit.
- Changing default config / example nodes → update `docs/user-manual.md`.

---

## When to Call This Skill

Call before:
- Writing any new screen, widget, or service
- Proposing UI copy or localization keys
- Touching build scripts, Makefile, or Xcode config
- Reviewing a PR that touches core VPN logic or App Store metadata
