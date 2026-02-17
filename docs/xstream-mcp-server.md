# XStream 本机 MCP Server（Go 版，Codex / Genmini）

该服务用于本机调试 XStream 的：

- macOS 配置与运行日志
- 账号登录 / MFA / 同步接口
- Flutter / Xcode 构建链路

## 1. 安装依赖

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xstream.svc.plus/tools/xstream-mcp-server
go mod tidy
```

## 2. 启动 MCP Server（stdio）

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xstream.svc.plus
./scripts/start-xstream-dev-mcp-server.sh
```

开发态脚本会自动加载项目根目录 `.env`（若存在）。

兼容入口：`./scripts/start-xstream-mcp-server.sh`（等价于 dev 启动脚本）。

## 3. 添加到 Codex MCP list

在 `~/.codex/config.toml` 添加：

```toml
[mcp_servers.xstream-dev]
type = "stdio"
command = "bash"
args = ["-lc", "cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xstream.svc.plus && ./scripts/start-xstream-dev-mcp-server.sh"]
startup_timeout_sec = 30
```

运行态（已安装 app）可并存配置：

```toml
[mcp_servers.xstream-runtime]
type = "stdio"
command = "bash"
args = ["-lc", "cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xstream.svc.plus && ./scripts/start-xstream-runtime-mcp-server.sh"]
startup_timeout_sec = 30
```

## 4. Genmini 连接示例

使用 `stdio`：

- command: `bash`
- args:
  - `-lc`
  - `cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xstream.svc.plus && ./scripts/start-xstream-dev-mcp-server.sh`

## 5. 可用工具

- `workspace_info`
- `macos_app_paths`
- `macos_tail_logs`
- `macos_read_sync_artifacts`
- `auth_login`
- `auth_mfa_verify`
- `auth_sync_pull`
- `auth_sync_ack`
- `flutter_pub_get`
- `flutter_analyze`
- `flutter_build_macos_debug`
- `flutter_build_ios_sim_debug`
- `xcode_build_macos_workspace`
- `xcode_mcp_doctor`

## 6. 说明

- macOS 构建优先使用 `Runner.xcworkspace`，避免 `.xcodeproj` 引发 CocoaPods 模块缺失。
- Xcode MCP server 若提示路径未授权，请设置：

```bash
export XCODEMCP_ALLOWED_FOLDERS="/Users/shenlan/workspaces/cloud-neutral-toolkit/xstream.svc.plus"
```

## 7. 推荐 .env 配置（本机调试）

```bash
XSTREAM_ACCOUNTS_BASE_URL=https://accounts.svc.plus
XSTREAM_ACCOUNTS_USERNAME=your_account
XSTREAM_ACCOUNTS_PASSWORD=your_password
XSTREAM_MCP_DEBUG=true
```

说明：

- `auth_login` 工具在未传 `username/password` 参数时，会自动读取 `.env` 中的账号密码。
- `XSTREAM_MCP_DEBUG=true` 会在 stderr 输出调试日志（自动脱敏 Authorization/Cookie）。

## 8. DMG 运行态内置 MCP（用于运行后调试）

`make macos-arm64` / `make macos-intel` 会自动把运行态 MCP 打进 app bundle：

`xstream.app/Contents/Resources/runtime-tools/xstream-mcp/`

包含文件：

- `xstream-mcp-server`
- `start-xstream-mcp-server.sh`
- `README.txt`

可直接在已安装应用上启动：

```bash
"/Applications/xstream.app/Contents/Resources/runtime-tools/xstream-mcp/start-xstream-mcp-server.sh"
```

## 9. OpenClaw 联调示例（stdio）

将 OpenClaw 的 MCP server command 指向 app bundle 内置 launcher：

- command: `bash`
- args:
  - `-lc`
  - `"/Applications/xstream.app/Contents/Resources/runtime-tools/xstream-mcp/start-xstream-mcp-server.sh"`

这样可以在“已安装运行态”直接执行配置与同步调试（`macos_app_paths` / `macos_read_sync_artifacts` / `auth_sync_pull` 等）。

## 10. 并存模式建议

建议同时保留两条 MCP 连接：

- `xstream-dev`：调试源码与构建流程（`flutter_*`、`xcode_*`、接口联调）
- `xstream-runtime`：调试已安装 app 的真实运行态数据（配置/日志/同步）

Makefile 快捷入口：

```bash
make xstream-mcp-start-dev
make xstream-mcp-start-runtime
```
