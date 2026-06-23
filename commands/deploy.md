---
name: "Deploy"
description: 发布管理 — 查看待发布列表或执行发布
category: Deploy
tags: [deploy, publish, ldc]
---

发布管理：查看待发布列表或执行已审批的发布。

**输入**: `$ARGUMENTS` 格式为 `[action] [env]`
- `action`: `list`（查看列表）或 `publish`（执行发布），默认 `list`
- `env`: `test` 或 `prod`，如果为空则交互式选择

示例：
- `/deploy list test` → 查看测试环境待发布列表
- `/deploy publish prod` → 发布生产环境
- `/deploy list` → 交互式选择环境，查看列表
- `/deploy publish` → 交互式选择环境，执行发布
- `/deploy` → 默认 list，交互式选择环境

**步骤**

1. **前置检查**

   按照 `ldc-deploy` skill 中的前置检查流程：
   - 检查 `ldc` 是否安装（`which ldc`），未安装则询问是否自动安装
   - 检查登录状态（`ldc whoami`）
   - 未通过则按 skill 中的提示处理并中止

2. **读取项目配置**

   按照 `ldc-deploy` skill 中的配置读取流程：
   - 读取当前项目 `.claude/deploy.json`
   - 不存在则提示 "运行 `/init` 初始化配置" 并中止

3. **解析参数**

   从 `$ARGUMENTS` 中解析 action 和 env：
   - 第一个词是 action（`list` 或 `publish`）
   - 第二个词是 env（`test` 或 `prod`）
   - 如果只有 action 没有 env → 使用 AskUserQuestion 选择环境
   - 如果都为空 → action 默认 `list`，env 交互式选择

4. **生产环境发布确认**

   如果 action 为 `publish` 且环境为 `prod`，**必须**使用 AskUserQuestion 进行二次确认。

5. **执行命令**

   根据 action 执行对应命令：

   **list（查看待发布列表）：**
   ```bash
   ldc deploy list <appId>
   ```

   **publish（执行发布）：**
   ```bash
   ldc deploy publish <appId>
   ```

   其中 `<appId>` 根据目标环境从 `.claude/deploy.json` 中读取。

   设置 `timeout: 120000`（2 分钟）

6. **展示结果**

   - list 成功：展示待发布记录列表
   - publish 成功：展示发布结果，输出 cloudUrl
   - 失败：展示错误信息和排查建议

**护栏**
- 生产环境发布前**必须**二次确认
- 不执行 `ldc review` 审批操作
- 不执行 `ldc logout`
