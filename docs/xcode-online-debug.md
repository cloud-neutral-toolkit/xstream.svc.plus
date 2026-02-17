# Xcode 在线调试（macOS / iOS）

本文档用于在 Xcode 中稳定进行 `xstream.svc.plus` 的在线调试（断点、变量、日志、Flutter 热重载协同）。

## 1. 一次性准备

在项目根目录执行：

```bash
./scripts/xcode-debug-bootstrap.sh
# 或
make xcode-mcp-doctor
```

该脚本会完成：

- `flutter pub get`
- `ios` / `macos` 的 `pod install`
- 生成并同步 `Flutter/flutter_lldbinit`
- 生成 `.app_filename`（`generated` 与 `ephemeral` 两处）
- 输出可直接用于 Xcode MCP Server 的工程路径

## 1.1 Xcode MCP Server 对接

`xstream.svc.plus` 统一使用以下 workspace 路径（推荐）：

- iOS: `ios/Runner.xcworkspace`
- macOS: `macos/Runner.xcworkspace`

注意：

- 直接用 `Runner.xcodeproj` 构建可能出现 `path_provider_foundation/shared_preferences_foundation/url_launcher_macos` 模块缺失。
- Xcode 与 Xcode MCP Server 都应优先指向 `Runner.xcworkspace`。

若你通过 Xcode MCP Server 执行构建/测试，请先执行一次：

```bash
make xcode-mcp-doctor
```

## 2. macOS 在线调试

1. 打开工程：`macos/Runner.xcworkspace`
2. Scheme 选择：`Runner`
3. Configuration 选择：`Debug`
4. 直接 `Run`（`Cmd + R`）

说明：

- 已配置 `customLLDBInitFile=$(SRCROOT)/Flutter/flutter_lldbinit`（macOS）
- 工程脚本会在构建时同时维护 `Flutter/generated/.app_filename` 和 `Flutter/ephemeral/.app_filename`

## 3. iOS 在线调试

1. 打开工程：`ios/Runner.xcworkspace`
2. Scheme 选择：`Runner`
3. 设备选择：iPhone Simulator 或真机
4. Configuration 选择：`Debug`
5. `Run`（`Cmd + R`）

说明：

- iOS Scheme 保持 Flutter 官方默认（不写死 custom LLDB init），由 Flutter 工具链在调试构建时处理 LLDB 注入
- 如切换 Flutter / Xcode 版本后出现调试问题，重新执行 `./scripts/xcode-debug-bootstrap.sh`

## 4. 常见问题

### 4.1 `Unable to find app name ... .app_filename does not exist`

执行：

```bash
./scripts/xcode-debug-bootstrap.sh
```

并重试构建。

### 4.2 Pods 不一致

在对应平台目录执行：

```bash
pod install
```

### 4.3 Flutter 调试符号不生效

确认当前 Scheme 是 `Debug`，且 `customLLDBInitFile` 为：

- macOS: `$(SRCROOT)/Flutter/flutter_lldbinit`
