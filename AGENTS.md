# Agents Guidelines

本文件为整个仓库的协作说明，适用于 `Xstream/` 下的所有文件与子目录。请在修改代码或文档前阅读并遵循以下约定。

> **⚠️ AI-Critical:** Any AI-generated output that violates Section 5 (Compliance) must be treated as invalid and rejected.

---

## 1. 项目概览

- **前端/客户端：** Flutter 应用位于 `lib/`，通过多屏幕（`screens/`）、服务层（`services/`）、工具库（`utils/`）以及组件库（`widgets/`）组织代码。
- **原生桥接：** `lib/utils/native_bridge.dart` 负责 Swift ↔ Flutter 通信；`go_core/` 提供 Go 编写的跨平台 FFI 桥接（iOS / Android / Linux / Windows），通过 `lib/bindings/bridge_bindings.dart` 暴露到 Flutter。
- **模板与配置：** `lib/templates/` 保存生成 Xray 配置的文本模板；`assets/` 存放静态资源与默认配置；`docs/` 内含平台构建与使用文档。
- **构建脚本：** `Makefile` 和 `scripts/` 提供多平台打包流程，`make help` 查看所有可用目标。

---

## 2. 目录速览

| 路径 | 说明 |
|------|------|
| `lib/main.dart` | 应用入口、`MainPage` 导航容器 |
| `lib/screens/` | 各功能页面（home / settings / subscription / login / logs / about / help） |
| `lib/services/` | 业务服务层（VPN 配置、账号同步、DNS、遥测等） |
| `lib/utils/` | 共享工具（`app_theme` / `app_logger` / `global_config` / `native_bridge`） |
| `lib/widgets/` | 跨界面复用组件（`app_breadcrumb` / `log_console` / `permission_guide_dialog` 等） |
| `lib/l10n/` | 中英双语字符串表 |
| `lib/templates/` | Xray 及 launchd/systemctl 配置文本模板 |
| `go_core/` | Go FFI 层（bridge.go + bridge_\<platform\>.go），macOS 走 Swift 原生，无对应 .go |
| `Runbook/` | 运维手册（发版、归档、代码质量检查等） |
| `skills/` | AI 辅助开发的可调用 skill 集合 |

---

## 3. 开发约定

### 3.1 通用流程

1. 修改前确认是否已有同类模块可复用，避免重复实现。
2. 所有代码变更必须通过格式化与静态检查：
   - Flutter/Dart：`dart format .` 与 `flutter analyze`（零 issue）。
   - Go：`go fmt ./...` 与 `go vet ./...`。
3. 改动影响构建流程或原生行为时，PR 描述中注明目标平台及验证命令。
4. 文档、脚本或模板的行为变更需同步更新 `docs/` 或脚本注释。

### 3.2 Flutter / Dart 代码

- **lint**：遵循 `analysis_options.yaml`（基于 `flutter_lints`），不得全局关闭规则；局部例外用 `// ignore: <rule> — <reason>`。
- **l10n**：UI 文本必须通过 `context.l10n.get('key')` 获取；新增 key 必须同时添加 `en` 与 `zh` 两个译文。
- **状态管理**：复用 `GlobalState` / `ValueNotifier`，不直接操作底层服务对象。
- **日志**：通过 `addAppLog(...)` 写入；**禁止** 在生产代码中使用 `print`；不得记录密码、token 等敏感信息。
- **异步**：所有 async 调用必须 `await` 并捕获异常；界面层用 `SnackBar` / `Dialog` 反馈错误。
- **原生交互**：优先通过服务层（`VpnConfigService` / `NativeBridge`）交互；Screen widget 不得直接处理文件路径、权限或 FFI 细节。
- **Screen AppBar 规范**：嵌入 `MainPage`（`IndexedStack`）的 Screen **不得**渲染自己的 `AppBar`（由外层统一提供面包屑）；通过构造参数（如 `breadcrumbItems`）区分"嵌入"和"独立 push"两种场景。

### 3.3 Go FFI 代码

- 每个导出函数必须返回字符串结果或明确的错误码，不允许 panic 传出到 Dart。
- `C.CString` / `C.malloc` 分配的指针必须在 Go 端提供释放函数（参见 `FreeCString`）；Dart 侧调用后务必释放。
- 平台差异逻辑放 `bridge_<platform>.go`；`bridge.go` 仅保留公共导出函数声明。
- **macOS 无对应 Go 桥接**：macOS 系统网络由 Swift `PacketTunnelProvider` 实现，`go_core/` 中不存在 `bridge_macos.go`。

### 3.4 资源与模板

- 修改 `lib/templates/` 后同步更新 `services/vpn_config_service.dart` 中的生成逻辑。
- 新增静态资源放 `assets/` 并在 `pubspec.yaml` 中声明。
- 调整默认配置或示例节点时同步更新 `docs/user-manual.md`。

---

## 4. 构建与版本

### 4.1 版本号

版本唯一来源：`pubspec.yaml` 中的 `version: X.Y.Z-BUILD`。

- `X.Y.Z` → Xcode `MARKETING_VERSION`
- `BUILD` → Xcode `CURRENT_PROJECT_VERSION`（整数，每发布递增）

**Xcode Archive 前置步骤（必须执行）：**

```bash
make sync:macos:config
```

此命令重新生成 `macos/Flutter/ephemeral/Flutter-Generated.xcconfig`，确保 Xcode 读取到正确的版本号。

### 4.2 常用 Make 目标

| 目标 | 说明 |
|------|------|
| `make build:macos:arm64` | Apple Silicon macOS release + DMG |
| `make build:macos:x64` | Intel macOS release + DMG |
| `make sync:macos:config` | 同步 pubspec.yaml 版本 → Generated.xcconfig |
| `make build:ios:ipa` | iOS release IPA（需 macOS + Xcode） |
| `make build:windows:x64` | Windows x64 release |
| `make build:linux:x64` | Linux x64 release |
| `make clean` | 清理 Flutter 及生成物 |
| `make fix:macos:signing` | 清理 xattr，修复签名状态 |

### 4.3 PR Checklist

- [ ] `flutter analyze` 零 issue
- [ ] `dart format .` 已应用
- [ ] `CHANGELOG.md` 已更新（若为用户可见变更）
- [ ] 对应平台构建已在本地验证，PR 描述注明所用命令

---

## 5. 合规约束（AI-Critical，不可协商）

> All human contributors and **all AI agents** must follow these rules without exception.

### 5.1 产品定位

Xstream 是面向 **macOS App Store** 发行的 **合法系统级 VPN / Secure Network Tunnel**。

合法用途：网络安全 · 隐私保护 · 连接稳定性 · 网络加速

### 5.2 架构约束

- 系统网络接管**仅允许**通过 **NEPacketTunnelProvider（Packet Tunnel）** 实现。
- **禁止**：用户态 TUN hack、TUN + SOCKS forwarding、sudo 路由修改、代理环境变量。
- DNS（含 DoT）是安全隧道的组成部分，不得描述为旁路或变通手段。

### 5.3 语言约束

| ✅ 允许使用 | ❌ 禁止使用 |
|------------|------------|
| Secure Tunnel | bypass / circumvent / break through |
| System VPN | 任何国家 / 地区名称 |
| Packet Tunnel | 审查 / 封锁 / 绕过 / 翻越 |
| Encrypted Network | 政治或监管暗示 |
| Network Acceleration / Reliability | — |
| Privacy Protection | — |
| System-level Networking | — |

---

## 6. 文档与日志

- 新增功能或显著行为更改必须同步更新 `CHANGELOG.md`。
- 面向用户的流程说明请补充或修改 `docs/` 目录下的相关指南。
- 运维操作请参考 `Runbook/` 目录；技能知识请参考 `skills/` 目录。

---

如需在子目录定义额外规范，可在该目录下创建新的 `AGENTS.md`，层级越深优先级越高。
