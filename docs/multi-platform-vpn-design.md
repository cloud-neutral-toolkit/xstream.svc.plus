# 跨平台代理内核与 TUN 设计

本文档总结了 XStream 在各主要平台上嵌入 xray-core 及接管流量的推荐方案，便于后续开发与维护。

## 平台与模式对照

| 平台   | 推荐模式                             | 主要原因 |
|--------|-------------------------------------|---------|
| iOS    | PacketTunnelProvider + `libxray.a`  | 使用官方 NE 框架，可安全上架 |
| macOS  | PacketTunnelProvider + `libxray.dylib` | 系统级入口统一为 Packet Tunnel |
| Android| VpnService + `libxray.so`           | 官方接口，无需 root |
| Windows| WinTun + `libxray.dll`              | 用户态驱动，无需管理员权限 |
| Linux  | 用户态 TUN + xray-core/`libxray.so`  | 结合 systemd 或用户态运行 |

## 桥接方式建议

| 平台   | 调用链举例                              | 工具链 |
|--------|---------------------------------------|-------|
| iOS    | Swift ⟶ `libxray.a` (C 导出)         | `gomobile bind` 生成 `.framework` |
| macOS  | Swift/ObjC ⟶ `.dylib`                | `dlopen` 或 XPC 调用 CLI |
| Android| Dart FFI ⟶ `libxray.so`              | 与 VpnService 协作 |
| Windows| Dart FFI ⟶ `libxray.dll`             | Win32 FFI 结构映射 |
| Linux  | Dart FFI ⟶ `.so` / 管理 CLI          | 可结合 D-Bus 或 systemd |

## 内置 DNS 分流示例

使用 xray-core 的 DNS 能力即可适配所有平台：

```json
"dns": {
  "servers": [
    { "address": "https://1.1.1.1/dns-query", "domains": ["geosite:geolocation-!cn"] },
    { "address": "223.5.5.5", "domains": ["geosite:cn"] },
    "localhost"
  ],
  "strategy": "IPIfNonMatch",
  "disableCache": false
}
```

无需系统级 DNS 劫持即可实现智能分流。

## 流量接管流程概览

```mermaid
flowchart TD
    subgraph User Space
        A[VPN/TUN Adapter] --> C[xray-core (lib)]
        C --> D[Reality / VLESS / Trojan Outbound]
        C --> E[内置 DNS 分流器]
    end
```

## 零感知原则

- **不修改系统代理**：通过虚拟网卡拦截。
- **热插拔节点**：动态重启 xray-core 实例，替换 JSON 配置。
- **智能分流**：内置 geoip/geosite 自动处理。
- **无需 Root/Admin**：TUN/NE/VpnService 均为用户态。

## 建议目录结构

```
core/    - xray-core 包装库
bridge/  - 各平台 FFI/原生桥接
app/     - Flutter UI 与 VPN 控制器
```

核心逻辑统一封装在 Go，供不同平台通过 FFI 调用。

## 推荐策略总结

- 统一使用嵌入式 xray-core 库作为代理内核。
- 通过虚拟网卡（NE/VpnService/WinTun/用户态 TUN）接管流量。
- Flutter + Dart FFI 封装各平台桥接，保证 UI 一致性。
- 避免修改系统代理和需要 root，提升可上架与易用性。
