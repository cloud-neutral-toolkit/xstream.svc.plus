# Runbook: Version Release Cut

**适用场景**：发布新版本，包括更新版本号、切 release 分支、打 tag。  
**最后更新**：2026-03-08

---

## 分支策略速查

| 分支 | 用途 |
|------|------|
| `main` | Preview / 持续迭代，可能比 production 超前 |
| `release/vX.Y` | 生产发行线，只允许 release manager cherry-pick 更新 |

详见 `skills/release-branch-policy/SKILL.md`。

---

## Step 1：确认 main 状态

```bash
git checkout main
git pull origin main
git status          # 必须干净
flutter analyze     # 必须零 issue
```

---

## Step 2：更新版本号

编辑 `pubspec.yaml`：

```yaml
version: X.Y.Z+BUILD
```

更新 `CHANGELOG.md`：

```markdown
## X.Y.Z – YYYY-MM-DD
### Added
- ...
### Fixed
- ...
```

提交：

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "chore: bump version to X.Y.Z+BUILD"
git push origin main
```

---

## Step 3：切 release 分支

```bash
git checkout -b release/vX.Y
git push origin release/vX.Y
```

在 GitHub 上为 `release/vX.Y` 应用 Branch Ruleset（参见 `skills/release-branch-policy/scripts/apply_ruleset.sh`）：

```bash
skills/release-branch-policy/scripts/apply_ruleset.sh <owner> <repo>
```

---

## Step 4：打 Tag

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

---

## Step 5：macOS 构建归档

跳转执行 `Runbook/Release-macOS-Archive.md` 的完整流程。

---

## Step 6：验证 Checklist

- [ ] `pubspec.yaml` 版本 = tag = app bundle 版本
- [ ] `CHANGELOG.md` 已更新
- [ ] `release/vX.Y` 分支已在 GitHub 上创建并保护
- [ ] App Store Connect / DMG 已上传
- [ ] CI 绿灯（若有）

---

## 回滚计划

```bash
# 删除错误 tag
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z

# 删除错误 release 分支（需先移除 Branch Protection）
git push origin --delete release/vX.Y
```
