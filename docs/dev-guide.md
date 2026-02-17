# 开发者构建指南（macOS）

本指南适用于希望在 macOS 上本地构建和调试 XStream 项目的开发者。

如果你使用 Xcode 进行 iOS/macOS 联调，请先阅读：

- [Xcode 在线调试（macOS / iOS）](xcode-online-debug.md)
- [本机 MCP Server（Codex / Genmini）](xstream-mcp-server.md)

## 环境准备

### 1. 安装 Flutter

使用 Homebrew 安装 Flutter： brew install --cask flutter

或者参考官方安装指南：Flutter 安装文档

2. 安装 Xcode 和配置

前往 App Store 或 Apple Developer 官网安装最新版 Xcode。

初次安装后运行初始化命令： sudo xcodebuild -runFirstLaunch
安装命令行工具（如果未安装）： xcode-select --install

3. 安装 CocoaPods（iOS/macOS 必需）

sudo gem install cocoapods

4. 拉取依赖并构建

flutter pub get
sh scripts/generate_icons.sh  # 生成 iOS App 图标
flutter build macos
开发调试
使用 VS Code 或 Android Studio 打开项目根目录，可执行如下命令调试：
flutter run -d macos
或使用调试按钮直接运行项目。

# 项目结构说明

## 核心配置文件
- `pubspec.yaml` - Flutter项目配置文件，包含依赖、版本等信息
- `Makefile` - 构建脚本，定义各种构建任务
- `analysis_options.yaml` - Dart代码分析配置

## Flutter应用代码
- `lib/` - 主要Dart代码目录
  - `main.dart` - 应用入口文件
  - `screens/` - 界面文件（主屏幕、设置屏幕等）
  - `services/` - 服务层代码（VPN配置、更新服务、遥测等）
  - `utils/` - 工具类（主题、配置、日志等）
  - `widgets/` - UI组件（按钮、输入框、控制台等）
  - `templates/` - 配置模板（Xray配置、系统服务等）
  - `bindings/` - FFI绑定文件

## 平台特定代码
- `android/` - Android平台代码和配置
- `ios/` - iOS平台代码和配置
- `macos/` - macOS平台代码和配置
- `windows/` - Windows平台代码和配置
- `linux/` - Linux平台代码和配置
- `web/` - Web平台代码和配置

## Go核心模块
- `go_core/` - Go语言编写的核心功能模块
  - `bridge.go` - 主要桥接代码
  - `bridge_*.go` - 各平台特定的桥接实现

## 构建和部署
- `build_scripts/` - 各平台构建脚本
- `scripts/` - 辅助脚本（图标生成、清理等）
- `msix_config.yaml` - Windows MSIX包配置

## 文档和资源
- `docs/` - 项目文档
- `assets/` - 静态资源（图标、Logo等）
- `bindings/` - 原生代码绑定文件

# 常见问题
构建失败、权限错误
检查是否正确授予 macOS 网络和文件访问权限

使用 flutter clean 清除缓存后重新构建


macos/
└── Runner/
    ├── AppDelegate.swift               # 保留主入口和 Flutter channel 注册逻辑
    ├── NativeBridge+ConfigWriter.swift # 包含 writeConfigFiles、writeFile 等配置写入相关函数
    ├── NativeBridge+XrayInit.swift     # 包含 runInitXray 的 AppleScript 权限处理与初始化逻辑
    ├── NativeBridge+ServiceControl.swift # 启动/停止/check 服务的 launchctl 相关逻辑
    └── NativeBridge+Logger.swift       # logToFlutter 日志通道封装

lib/services/update/
├── models/update_info.dart         ✅ 原 `UpdateInfo` 数据结构已迁移
├── update_platform.dart            ✅ 平台识别 + 渠道（stable/latest）支持
├── update_service.dart             ✅ 使用 Pulp REST API 查询版本
└── update_checker.dart             ✅ 定时检查 + 弹窗 UI 封装

- DMG filename now follows the pattern:
  - `xstream-release-<tag>.dmg` if tagged on main branch
  - `xstream-latest-<commit>.dmg` if untagged on main
  - `xstream-dev-<commit>.dmg` for non-main branches
