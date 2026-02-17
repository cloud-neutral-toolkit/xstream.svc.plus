# macOS Menu Bar Regression Checklist

最小联调清单（点击路径 + 预期结果）：

1. 启动应用
- 点击路径：终端执行 `make macos-debug-run`
- 预期结果：应用启动成功，菜单栏出现 XStream 图标。

2. 菜单状态默认值
- 点击路径：菜单栏图标 -> 展开菜单
- 预期结果：显示 `Status: Disconnected`，`Node: -`，并有 `Start Acceleration` 按钮。

3. 显示主窗口
- 点击路径：菜单栏图标 -> `Show Main Window`
- 预期结果：主窗口前置激活，无崩溃。

4. 打开日志
- 点击路径：菜单栏图标 -> `Open Logs`
- 预期结果：Finder 打开日志目录；主窗口切到“日志”页签。

5. 编辑规则
- 点击路径：菜单栏图标 -> `Edit Rules`
- 预期结果：系统打开 `vpn_nodes.json`（或关联编辑器）；主窗口切到“节点/订阅”相关页签。

6. 代理模式切换（Tun）
- 点击路径：菜单栏图标 -> `Proxy Mode` -> `Tun Mode`
- 预期结果：`Tun Mode` 显示勾选；应用连接模式切换为 VPN/Tun。

7. 代理模式切换（Proxy Only）
- 点击路径：菜单栏图标 -> `Proxy Mode` -> `Proxy Only`
- 预期结果：`Proxy Only` 显示勾选；应用连接模式切换为仅代理。

8. 启动加速
- 点击路径：菜单栏图标 -> `Start Acceleration`
- 预期结果：状态变为 `Status: Connected`；`Node: {节点名}`；按钮文案变为 `Stop Acceleration`。

9. 重连
- 点击路径：菜单栏图标 -> `Reconnect`
- 预期结果：节点服务执行 stop + start；最终保持 Connected，无崩溃。

10. 停止加速
- 点击路径：菜单栏图标 -> `Stop Acceleration`
- 预期结果：状态变为 `Disconnected`，保留节点名显示。

11. 开机启动开关
- 点击路径：菜单栏图标 -> `Launch at Login`
- 预期结果：勾选状态可切换（macOS 13+）。

12. 退出（保留连接）
- 点击路径：菜单栏图标 -> `Quit`
- 预期结果：应用退出；不额外执行 stop。

13. 退出并停止加速
- 点击路径：菜单栏图标 -> `Quit & Stop Acceleration`
- 预期结果：先 stop 节点服务，再退出应用。
