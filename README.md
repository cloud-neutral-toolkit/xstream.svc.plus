# XStream

<p align="center">
  <img src="assets/logo.png" alt="Project Logo" width="200"/>
</p>

**XStream** 是一个用户友好的图形化客户端，用于便捷管理 Xray-core 多节点连接配置，优化网络体验，助您畅享流媒体、跨境电商与开发者服务（如 GitHub）。

---

## ✨ 功能亮点

- 多节点支持，快速切换
- 实时日志输出与故障诊断
- 支持 macOS 权限验证与服务管理
- 解耦式界面设计，支持跨平台构建
- Windows/Linux 版本最小化时自动隐藏到系统托盘（右下角）
- Windows 版本支持计划任务部署与后台运行
- Windows 版本现已支持生成 MSIX 安装包并上架 Microsoft Store

---

## 📦 支持平台

| 平台     | 架构     | 测试状态   |
|----------|----------|------------|
| macOS    | arm64    | ✅ 已测试   |
| macOS    | x64      | ⚠️ 未测试   |
| Linux    | x64      | ⚠️ 未测试   |
| Linux    | arm64    | ⚠️ 未测试   |
| Windows  | x64      | ✅ 已测试   |
| Android  | arm64    | ⚠️ 未测试   |
| iOS      | arm64    | ⚠️ 未测试   |

---


## 🚀 快速开始

请根据使用身份选择：

- 📘 [用户使用手册](docs/user-manual.md)
- 🛠️ [开发者文档（macOS 开发环境搭建）](docs/dev-guide.md)
- 🧪 [Xcode 在线调试（macOS / iOS）](docs/xcode-online-debug.md)
- 🤖 [本机 MCP Server（Codex / Genmini）](docs/xstream-mcp-server.md)
- 📱 [iOS 设计文档](docs/ios-design.md)
- 🐧 [Linux systemd 运行指南](docs/linux-xray-systemd.md)
- 🪟 [Windows 计划任务运行指南](docs/windows-task-scheduler.md)

切换到 **隧道模式** 后，应用会使用 macOS Packet Tunnel（NEPacketTunnelProvider）接管系统流量。

更多平台构建步骤与桥接架构可参考下列文档：

- [Windows 构建指南](docs/windows-build.md)
- [Linux 构建须知](docs/linux-build.md)
- [iOS 设计文档](docs/ios-design.md#xray-core-%E9%9B%86%E6%88%90)
- [FFI 桥接架构](docs/ffi-bridge-architecture.md)

## 📚 许可证与致谢

- 本项目整体遵循 [GNU GPLv3](LICENSE) 开源协议。
- 核心网络功能依赖 [Xray-core](https://github.com/XTLS/Xray-core) ，遵循 Mozilla Public License 2.0。
- 桥接库 [libXray](https://github.com/XTLS/libXray) 使用 MIT License 发布。
