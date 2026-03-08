# Runbook 目录

本目录包含 Xstream 项目的运维手册和故障排查文档。

---

## 📚 文档列表

### 🚀 发版流程

| 文档 | 说明 |
|------|------|
| [Release-Version-Cut.md](./Release-Version-Cut.md) | 完整版本发布流程：更新版本号、切 release 分支、打 tag |
| [Release-macOS-Archive.md](./Release-macOS-Archive.md) | Xcode Archive 归档发布：配置同步、签名、公证、DMG 打包 |

### 🔍 质量保障

| 文档 | 说明 |
|------|------|
| [Code-Quality-Check.md](./Code-Quality-Check.md) | PR 合并前代码质量验收：lint、格式化、l10n、页面渲染 |

### 🚨 故障排查

| 文档 | 说明 |
|------|------|
| [Tunnel-Mode-Site-Diff-From-Proxy-Mode.md](./Tunnel-Mode-Site-Diff-From-Proxy-Mode.md) | Tunnel Mode 与 Proxy Mode 站点可访问性差异排查 |

---

## 📝 Runbook 编写规范

每个 Runbook 应包含：

1. **标题 + 适用场景**：说明何时使用本手册
2. **前置条件**：执行前需满足的环境要求
3. **步骤（Step N）**：有序、可重复执行的操作
4. **验证方法**：确认步骤成功的检查命令或标准
5. **回滚计划**：操作失败时的应急方案

## 🎯 命名规范

```
[领域]-[动作描述].md
示例：Release-macOS-Archive.md / Fix-API-Timeout.md
```

---

## 🔗 相关参考

- 开发约束规范：[`skills/xstream-dev-constraints/SKILL.md`](../skills/xstream-dev-constraints/SKILL.md)
- 分支策略：[`skills/release-branch-policy/SKILL.md`](../skills/release-branch-policy/SKILL.md)
- 全局协作说明：[`AGENTS.md`](../AGENTS.md)
