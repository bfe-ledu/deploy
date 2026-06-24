---
name: "Rollback"
description: 回滚到已发布版本的上一版本
category: Deploy
tags: [deploy, rollback, ldc]
---

回滚到上一发布版本。`$ARGUMENTS` 为 `test` 或 `prod`，为空则交互选择。

## 编排流程

1. **前置检查**
   - `Bash: which ldc` — 未安装提示安装命令
   - `Bash: ldc whoami` — 未登录提示 `/login`

2. **读取项目配置**
   - `Read: .claude/deploy.json`
   - 不存在 → 提示执行 `/init` 并结束

3. **确定回滚环境**
   - `$ARGUMENTS` 包含 `test` → 环境为 test，使用 `apps.test.appId`
   - `$ARGUMENTS` 包含 `prod` → 环境为 prod，使用 `apps.prod.appId`
   - `$ARGUMENTS` 为空 → `AskUserQuestion` 选择环境：
     - 选项："test"（测试环境）、"prod"（生产环境）

4. **二次确认（所有环境必须）**
   - `AskUserQuestion`：
     - 问题："确认要回滚 <环境名> 环境到上一版本吗？这是破坏性操作。"
     - 选项："确认回滚"、"取消"

5. **执行回滚**
   - `Bash: ldc deploy rollback <appId>`（timeout: 120000）
   - 输出回滚结果

## 安全约束

- 任何环境的回滚操作都必须二次确认
- 不执行 `ldc review` / `ldc logout`
