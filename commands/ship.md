---
name: "Ship"
description: 一键构建并发布项目到未来云（测试/生产环境）
category: Deploy
tags: [deploy, build, ship, ldc]
---

一键构建并发布。`$ARGUMENTS` 为 `test` 或 `prod`，为空则交互选择。

## 编排流程

1. **前置检查**
   - `Bash: which ldc` — 未安装提示安装命令
   - `Bash: ldc whoami` — 未登录提示 `/login`

2. **读取项目配置**
   - `Read: .ldc.json`
   - 不存在 → 提示执行 `/init` 并结束

3. **确定部署环境**
   - `$ARGUMENTS` 包含 `test` → 环境为 test
   - `$ARGUMENTS` 包含 `prod` → 环境为 prod
   - `$ARGUMENTS` 包含 `pre` → 环境为 pre
   - `$ARGUMENTS` 为空 → `AskUserQuestion` 选择环境：
     - 选项：`test`（测试环境）、`prod`（生产环境）、`pre`（预发环境，如已配置）

4. **生产环境二次确认**
   - 环境为 `prod` → `AskUserQuestion`：
     - 问题："确认要部署到生产环境吗？"
     - 选项："确认部署"、"取消"

5. **选择分支**
   - `Bash: git branch -r --sort=-committerdate | head -20`
   - 解析输出，去除 `HEAD` 引用和 `origin/` 前缀，取最近 3 个分支
   - `AskUserQuestion`：
     - 问题："选择要部署的分支？"
     - 选项 1-3：最近 3 个分支（显示分支名 + 最近提交信息）
     - 选项 4："手动输入分支名"
   - 如果 `git branch -r` 无输出 → 让用户手动输入分支名

6. **执行构建发布**
   - `Bash: ldc ship <env> -b <branch>`（timeout: 600000）
   - 其中 `<env>` 为环境标识（test/prod/pre），ldc 会自动从 `.ldc.json` 读取对应 App ID
   - 输出构建进度和结果

## 安全约束

- 不执行 `ldc review` / `ldc logout`
