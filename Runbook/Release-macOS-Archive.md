# Runbook: macOS Archive & Distribution

**适用场景**：通过 Xcode Archive 打包 macOS 发行包（App Store 或公证 DMG）。  
**最后更新**：2026-03-08

---

## 前置条件

| 项目 | 要求 |
|------|------|
| Xcode | 15.0+ |
| Flutter | 已安装并在 `PATH` 中 |
| Apple 证书 | Distribution Certificate 已安装到 Keychain |
| Provisioning Profile | macOS App Store Profile（含 Network Extension entitlement）已下载 |
| Git 状态 | 工作区干净（`git status` 无未提交修改） |

---

## Step 1：更新 pubspec.yaml 版本号

```yaml
# pubspec.yaml
version: X.Y.Z+BUILD   # 例：0.3.6+1
```

规则：
- `X.Y.Z` → Xcode `MARKETING_VERSION`
- `BUILD` → Xcode `CURRENT_PROJECT_VERSION`（整数，每次发布递增）

---

## Step 2：同步 Xcode 配置

```bash
make sync:macos:config
```

**验证**：检查生成文件中版本号是否正确：

```bash
grep "FLUTTER_BUILD" macos/Flutter/ephemeral/Flutter-Generated.xcconfig
# 应输出：
# FLUTTER_BUILD_NAME=X.Y.Z
# FLUTTER_BUILD_NUMBER=BUILD
```

---

## Step 3：清理 Extended Attributes（避免签名报错）

```bash
make fix:macos:signing
# 等价于：xattr -rc .
```

---

## Step 4：Xcode Archive

1. 打开 Xcode → 选择 `Runner` scheme + `Any Mac` 设备
2. **Product → Archive**
3. 等待构建完成，Organizer 窗口自动弹出

**常见失败原因**：
- `Generated.xcconfig` 未更新 → 重新执行 Step 2
- Entitlement 不匹配 → 检查 `macos/Runner/Runner.entitlements` 与 Apple Developer Portal 的 capability 是否一致
- Network Extension App Group 未启用 → 在 Developer Portal 为主 App 和 Extension 两个 Bundle ID 都启用

---

## Step 5：分发

### App Store Connect 上传

在 Organizer 中选择 Archive → **Distribute App → App Store Connect → Upload**

### 公证 DMG（直接分发）

```bash
make build:macos:arm64   # 或 build:macos:x64（Intel）
```

脚本会自动：
1. `flutter build macos --release`
2. `create-dmg` 打包
3. `xcrun notarytool` 公证（需要 App Store Connect API Key 已配置）

---

## Step 6：验证

```bash
# 检查 app bundle 版本
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  build/macos/Build/Products/Release/xstream.app/Contents/Info.plist

/usr/libexec/PlistBuddy -c "Print CFBundleVersion" \
  build/macos/Build/Products/Release/xstream.app/Contents/Info.plist
```

输出应与 `pubspec.yaml` 中的版本一致。

---

## 回滚计划

若 Archive 后发现问题：
1. 在 App Store Connect 暂停此版本提交（若已上传）
2. 在 `pubspec.yaml` 回退版本号并重新走本 Runbook
3. Git tag 问题：`git tag -d vX.Y.Z && git push origin :vX.Y.Z`

---

## 参考

- `skills/release-branch-policy/SKILL.md` — 分支策略
- `docs/macos-build.md` — 详细构建环境配置
