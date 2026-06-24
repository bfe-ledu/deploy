---
name: "Deploy"
description: 发布管理 — 查看待发布列表或执行发布
category: Deploy
tags: [deploy, publish, ldc]
---

发布管理。`$ARGUMENTS` 格式 `[action] [env]`，action 为 `list`（默认）或 `publish`，env 为 `test` 或 `prod`。

## 编排流程

1. **前置检查**
   - `Bash: which ldc` — 未安装提示安装命令
   - `Bash: ldc whoami` — 未登录提示 `/login`

2. **读取项目配置**
   - `Read: .claude/deploy.json`
   - 不存在 → 提示执行 `/init` 并结束

3. **确定操作类型**
   - `$ARGUMENTS` 包含 `list` → 操作为 list
   - `$ARGUMENTS` 包含 `publish` → 操作为 publish
   - 未指定 → `AskUserQuestion` 选择：
     - 选项："list"（查看待发布列表）、"publish"（执行发布）

4. **确定环境**
   - `$ARGUMENTS` 包含 `test` → 环境为 test，使用 `apps.test.appId`
   - `$ARGUMENTS` 包含 `prod` → 环境为 prod，使用 `apps.prod.appId`
   - 未指定 → `AskUserQuestion` 选择：
     - 选项："test"（测试环境）、"prod"（生产环境）

5. **生产环境发布二次确认**
   - 操作为 `publish` 且环境为 `prod` → `AskUserQuestion`：
     - 问题："确认要在生产环境执行发布吗？"
     - 选项："确认发布"、"取消"

6. **执行命令**
   - list: `Bash: ldc deploy list <appId>`（timeout: 120000）
   - publish: `Bash: ldc deploy publish <appId>`（timeout: 120000）
   - 输出结果

## 安全约束

- publish + prod 必须二次确认
- 不执行 `ldc review` / `ldc logout`
