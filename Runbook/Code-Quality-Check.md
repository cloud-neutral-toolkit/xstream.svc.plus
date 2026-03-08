# Runbook: Code Quality Check

**适用场景**：PR 合并前、发布前、或在 CI 报告问题后的代码质量验收。  
**最后更新**：2026-03-08

---

## Step 1：Flutter / Dart 静态分析

```bash
cd /path/to/xstream.svc.plus

# 格式化（修改被格式化的文件）
dart format .

# 静态分析（必须 zero issues）
flutter analyze
```

### 常见 Issue & 修复

| Issue | 原因 | 修复 |
|-------|------|------|
| `unused_element` | 私有方法/变量未使用 | 删除或在适当位置调用 |
| `prefer_const_declarations` | 常量未用 `const` | 加 `const` 修饰 |
| `deprecated_member_use` | 使用了已废弃 API | 参考 Flutter 迁移指南替换 |
| `avoid_print` | 生产代码使用 `print` | 改用 `addAppLog(...)` |
| `undefined_getter` | 删除了 state 字段但未清理引用 | 找到所有引用并更新 |

如需局部抑制（合理情况）：

```dart
// ignore: prefer_const_declarations
```

**注意**：全局关闭 lint 规则是禁止行为（参见 `analysis_options.yaml`）。

---

## Step 2：Go FFI 代码检查

```bash
cd go_core
go fmt ./...
go vet ./...
```

如有测试：

```bash
go test ./...
```

---

## Step 3：l10n 完整性检查

确认所有新增 UI key 同时存在于 `en` 和 `zh` 两个 locale：

```bash
# 快速检查 key 数量是否一致（两个数字应相同）
grep -c '"' lib/l10n/app_localizations.dart
```

手动检查 `lib/l10n/app_localizations.dart` 中 `en` 和 `zh` 的 Map，key 数量必须相等。

---

## Step 4：关键页面渲染验证

```bash
flutter run -d macos
```

人工核查以下页面无崩溃、无白屏：

- [ ] Home（节点列表 + VPN 控制）
- [ ] Settings（各子设置项可展开）
- [ ] Subscription（订阅管理）
- [ ] Logs（日志输出正常）
- [ ] About（无重复面包屑）
- [ ] Help（无重复面包屑）
- [ ] Login / Account（居中布局正常）

---

## Step 5：分析日志留存

如需保留本次分析结果：

```bash
flutter analyze > analyze.log 2>&1
```

`analyze.log` 已在 `.gitignore` 中，可本地留存但不提交。

---

## 通过标准

| 检查项 | 要求 |
|--------|------|
| `flutter analyze` | **零 issue** |
| `dart format` | 无格式差异（`--output=none --set-exit-if-changed`） |
| `go vet` | 零警告 |
| l10n key 数量 | `en` == `zh` |
| 关键页面 | 无崩溃、无白屏 |
