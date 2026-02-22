# Apple Signing 与 Packet Tunnel 能力申请（macOS / iOS）

本文档说明以下环境变量对应的 Apple 能力申请与配置流程：

- `XSTREAM_APPLE_TEAM_ID`
- `XSTREAM_APP_GROUP_ID`
- `XSTREAM_MACOS_BUNDLE_ID`
- `XSTREAM_IOS_BUNDLE_ID`
- `XSTREAM_MACOS_PACKET_TUNNEL_BUNDLE_ID`
- `XSTREAM_IOS_PACKET_TUNNEL_BUNDLE_ID`

参考模板：项目根目录 `.env.example`。

## 1. 前置条件

1. 开通 Apple Developer Program（组织或个人均可）。
2. 使用同一个 Team 管理主 App 与 Packet Tunnel Extension。
3. 在 Xcode 中已安装可用签名证书。

## 2. 变量规划与约束

建议先在 `.env` 中完成标识规划，再进入 Apple 后台创建能力：

```dotenv
XSTREAM_APPLE_TEAM_ID=YOUR_TEAM_ID
XSTREAM_APP_GROUP_ID=group.com.example.xstream

XSTREAM_MACOS_BUNDLE_ID=xstream.svc.plus
XSTREAM_IOS_BUNDLE_ID=plus.svc.xstream

XSTREAM_MACOS_PACKET_TUNNEL_BUNDLE_ID=xstream.svc.plus.PacketTunnel
XSTREAM_IOS_PACKET_TUNNEL_BUNDLE_ID=plus.svc.xstream.PacketTunnel
```

必须满足：

1. 主 App 与 Packet Tunnel Extension 使用同一 `XSTREAM_APPLE_TEAM_ID`。
2. 主 App 与 Packet Tunnel Extension 共享同一 `XSTREAM_APP_GROUP_ID`。
3. `PacketTunnelProviderBundleId` 必须精确指向对应平台的 Packet Tunnel 扩展 Bundle ID。

## 3. 在 Apple Developer 申请能力

### 3.1 创建 App IDs（主 App + 扩展）

分别为 macOS / iOS 创建以下显式 App ID（不要使用通配符）：

1. 主 App Bundle ID（如 `xstream.svc.plus`、`plus.svc.xstream`）。
2. Packet Tunnel Extension Bundle ID（如 `xstream.svc.plus.PacketTunnel`、`plus.svc.xstream.PacketTunnel`）。

### 3.2 为 App IDs 开启 Capability

在对应 App ID 上启用：

1. `Network Extensions`，类型选择 `packet-tunnel-provider`。
2. `App Groups`。

说明：

1. 主 App 与 Packet Tunnel Extension 两个 App ID 都需要开启以上两项能力。
2. 如果后台权限选项尚未可用，需先确认 Team 权限并联系 Apple Developer 支持开通对应能力。

### 3.3 创建并绑定 App Group

1. 在 Developer 后台创建 App Group（如 `group.com.example.xstream`）。
2. 将该 App Group 同时绑定到主 App ID 与 Packet Tunnel Extension App ID。

## 4. 证书与 Provisioning Profiles

为 iOS 与 macOS 分别准备 Development / Distribution 配置文件，并确保：

1. Profile 包含正确的 Bundle ID。
2. Profile 中启用了 `Network Extensions` 与 `App Groups`。
3. 主 App 与扩展使用同一 Team 下的有效签名身份。

## 5. Xcode 工程对齐

在 `ios/Runner.xcworkspace` 与 `macos/Runner.xcworkspace` 中检查：

1. `Runner` 与 `PacketTunnel` 两个 Target 的 `Signing & Capabilities`。
2. 两个 Target 都已添加 `Network Extensions`（Packet Tunnel）与同一个 `App Groups`。
3. `PRODUCT_BUNDLE_IDENTIFIER` 与上文环境变量一致。

同时检查：

1. `ios/Runner/Info.plist` 的 `PacketTunnelProviderBundleId`。
2. `macos/Runner/Info.plist` 的 `PacketTunnelProviderBundleId`。

其值必须与对应平台的 Packet Tunnel 扩展 Bundle ID 完全一致。

## 6. 运行时权限行为

Xstream 运行时会通过 `NETunnelProviderManager` 注册并启动 Packet Tunnel 配置。需要注意：

1. App 可以自动注册配置（`load/saveToPreferences`）。
2. 系统授权由用户在系统弹窗中确认，不能由 App 静默放行。
3. 若状态为 `not_configured` 或启动失败，应引导用户完成系统权限向导后重试。

## 7. 自检清单（发布前）

1. 主 App 与 Packet Tunnel Extension 均启用 `packet-tunnel-provider`。
2. 两者 Team ID 一致。
3. 两者 App Group 一致。
4. `PacketTunnelProviderBundleId` 指向正确扩展 Bundle ID。
5. 首次启动能拉起系统 VPN 授权流程，授权后可稳定建立 System VPN。

