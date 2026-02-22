# OneXray -> Xstream 迁移矩阵（保持 UI 不变）

## 1. 范围

本矩阵用于将已观测到的 OneXray 运行链路，逐项映射到 Xstream 当前模块，并给出不改 UI 的迁移动作。

约束：

1. 仅更新控制面与数据面实现，不调整现有页面布局与交互入口。
2. Darwin 平台系统级网络入口固定为 `NEPacketTunnelProvider`。
3. 统一运行配置入口固定为 `config.json`（软链接切换选中节点）。

## 2. OneXray 运行链路（观测摘要）

基于本机运行态与二进制字符串可观测信息：

1. 主 App + `PacketTunnel.appex` 双进程协作。
2. `PacketTunnel.appex` 直接接管 `utun`。
3. 扩展内存在本地回环端口（TCP/UDP）与 SOCKS5 隧道痕迹。
4. 扩展内集成 `libXray` 与 `HevSocks5Tunnel` 相关链路。

## 3. 迁移矩阵

| OneXray 链路项 | Xstream 当前模块 | 当前状态 | 缺口 | 不改 UI 的迁移动作 | 里程碑 |
|---|---|---|---|---|---|
| 主 App 控制入口（start/stop/status） | `lib/utils/native_bridge.dart` + `darwin/MacosHostApi.swift` | 已具备 | 无 | 保持接口不变，继续以 `save/start/stop/getPacketTunnelStatus` 驱动 | M0 |
| `NETunnelProviderManager` 注册与启动 | `darwin/MacosHostApi.swift` | 已具备 | 无 | 保持现有 manager 生命周期与错误上报 | M0 |
| Packet Tunnel 扩展进程 | `ios/PacketTunnel/PacketTunnelProvider.swift` + `macos/PacketTunnel/PacketTunnelProvider.swift` | 已具备 | 无 | 保持 `PacketTunnelProvider` 为唯一 System VPN 入口 | M0 |
| `utun` 接管与系统路由生效 | Darwin `PacketTunnelProvider` + 系统 `setTunnelNetworkSettings` | 已具备 | 无 | 持续使用 profile 下发的 route/dns/mtu 参数 | M0 |
| 扩展内本地代理桥接（SOCKS/HTTP） | `lib/services/vpn_config_service.dart`（可生成 socks/http inbound） | 部分具备 | 扩展内未明确形成“packetFlow -> 本地 inbound -> libXray”闭环 | 在扩展内新增本地桥接层，打通到 `libXray` 运行实例 | M1 |
| 扩展内 libXray 生命周期 | `go_core/bridge_ios.go` + `XrayTunnelBridge` | 部分具备 | `SubmitInboundPacket` 当前为占位实现 | 增加真实包转发或切换为扩展内本地代理桥接模式 | M1 |
| Proxy Mode（仅本地代理） | `NativeBridge.startNodeService` / `StartXray` | 已具备 | 与 Tunnel 模式状态未完全统一 | 统一状态模型，不改 UI 入口 | M1 |
| Tunnel Mode（System VPN） | `startPacketTunnel` 流程 | 已具备 | 数据面回包链路需闭环 | 扩展内实现稳定双向数据路径 | M1 |
| 统一配置入口 | `config.json` 软链接逻辑（`lib/utils/native_bridge.dart`） | 已具备 | 无 | 固化“所有启动统一读取 config.json” | M0 |
| 状态与错误存储 | `PacketTunnelStatusStore` + App Group key | 已具备 | iOS/macOS group 常量需统一化 | 统一读取配置化 App Group，避免硬编码分叉 | M1 |
| 回环防护（TUN -> TUN loop） | 路由与配置生成层 | 待完善 | 出站网卡绑定与排除路由策略需增强 | 增加 `sockopt.interface` 注入与 `excludedRoutes` 策略 | M2 |
| 权限与签名一致性 | `docs/apple-network-extension-signing-setup.md` + entitlements | 已具备 | 运行前自动核验不足 | 增加构建前/启动前自动核验脚本 | M2 |
| 跨平台扩展位（Windows/Linux/Android） | `go_core/bridge_*` + `lib/services/*` | 部分具备 | 控制面语义尚未完全统一 | 抽象 Platform Tunnel Adapter，复用同一 UI 控制入口 | M3 |

## 4. 推荐落地顺序

1. M0：固定入口与控制面（不改 UI）。
2. M1：先打通 Darwin 扩展内稳定数据面闭环（优先本地代理桥接路径）。
3. M2：补齐回环防护、签名与权限自动核验。
4. M3：统一跨平台控制面语义，保持界面层零变更。

## 5. 关联文档

1. `docs/system-vpn-packet-tunnel-xray26.md`
2. `docs/packet-tunnel-libxray-feasibility.md`
