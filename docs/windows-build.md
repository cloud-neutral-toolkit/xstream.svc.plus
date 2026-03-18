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

为了降低对目标机器 VC Runtime 预装状态的依赖，脚本会优先从本机 Visual Studio Build Tools 的 redist 目录补齐 `msvcp140.dll`、`vcruntime140.dll` 和 `vcruntime140_1.dll`。

如果打包目录里缺少 `wintun.dll`，脚本还会自动从官方 `wintun.net` 下载 `Wintun 0.14.1`，校验 SHA-256 后提取 `bin/amd64/wintun.dll` 到发布目录。这样标准 ZIP 与单文件 launcher 都能在应用目录旁拿到 `wintun.dll`。

## 5. 单文件 Windows Launcher

如果你需要一个“单文件分发”的 `xstream.exe`，请执行：

```powershell
./build_scripts/package_windows_single_file.ps1
```

该脚本会生成：

- `build/windows/x64/portable/xstream.exe`

这个文件是一个 **self-extract launcher**：它会把 Flutter Windows 运行时、`flutter_windows.dll`、`data/`、插件 DLL 与 `libgo_native_bridge.dll` 一起嵌入到单个外层 `xstream.exe` 中，启动时自动解压到用户缓存目录后再拉起内层运行时。

> 说明：基于当前 Flutter Windows 发布形态，真正“无任何运行时文件、直接把 Flutter engine 和资源全部静态并入同一个原生 PE”的方式并不现实。这里提供的是可落地的单文件分发方案。

## 6. 打包 MSI 安装包

CI 发布的 Windows 安装包现在默认是 MSI。在 Windows 环境执行：

```powershell
./build_scripts/package_windows_msi.ps1
```

脚本会基于 `build/windows/x64/runner/Release/` 下的 Flutter Release 产物生成 `xstream-windows.msi`，并自动补齐 `libgo_native_bridge.dll`、VC Runtime 与 `wintun.dll`。

如果你还需要 Microsoft Store 分发包，项目仍然保留 MSIX 打包脚本：

```powershell
./build_scripts/package_windows_msix.ps1
```

该脚本会根据根目录下的 `msix_config.yaml` 创建 `.msix` 文件。
