# Windows 构建指南

本文档说明如何在 Windows 平台编译 XStream 所需的 `libgo_native_bridge.dll` 动态库并构建桌面应用。

## 1. 安装依赖

1. 安装 [Go](https://go.dev/dl/) 1.20+，并确保 `go` 在 `PATH` 中。
2. 安装 [Flutter](https://docs.flutter.dev/get-started/install/windows) SDK。
3. 安装 MinGW-w64，并确保 `x86_64-w64-mingw32-gcc` 在 `PATH` 中。

## 2. 编译 Go 共享库

在项目根目录执行：

```bash
bash build_scripts/build_windows.sh
```

该脚本会将 `go_core` 编译为 `bindings/libgo_native_bridge.dll`，供 Dart FFI 通过 `DynamicLibrary.open` 加载。

如果你在排查 `go build` 相关问题，也可以进入 `go_core/` 目录单独执行构建命令并检查 `CGO_ENABLED`、`CC` 和 MinGW 工具链是否正确。

## 3. 构建 Flutter 桌面应用

推荐直接执行：

```bash
make build-windows-x64
```

`build-windows-x64` 目标会先运行 `build_scripts/build_windows.sh`，再执行 `flutter build windows --release`。同时，Windows 的 CMake 安装步骤会把 `bindings/libgo_native_bridge.dll` 一并复制到 `build/windows/x64/runner/Release/`，避免生成缺少核心 bridge DLL 的安装目录。

如果你只想手动执行 Flutter 构建，也可以运行：

```bash
flutter clean
flutter pub get
flutter build windows
```

前提是你已经先生成了 `bindings/libgo_native_bridge.dll`。如果 DLL 缺失，CMake 会直接报错并停止构建。

## 4. Release Packaging

本地或 CI 打包 ZIP 时，请执行：

```powershell
./build_scripts/package_windows_bundle.ps1
```

该脚本会从 `bindings/libgo_native_bridge.dll` 复制最新 bridge 产物到 `build/windows/x64/runner/Release/`，然后将整个 Release 目录压缩为 `xstream-windows.zip`。

## 5. 打包 MSIX 以便上架 Microsoft Store

项目已经支持通过 [msix](https://pub.dev/packages/msix) 插件生成可上架 Microsoft Store 的安装包。在 Windows 环境执行：

```powershell
./build_scripts/package_windows_msix.ps1
```

脚本会根据根目录下的 `msix_config.yaml` 创建 `.msix` 文件，生成的安装包位于 `build/windows/x64/runner/Release/` 目录下。
