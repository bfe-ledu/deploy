---
name: "Build"
description: 仅构建项目（打包），不提交发布申请
category: Deploy
tags: [deploy, build, ldc]
---

仅构建项目，不提交发布申请。适合提前验证构建是否通过。

**输入**: `$ARGUMENTS` 可以是环境标识 `test` 或 `prod`。如果为空则交互式选择。

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

3. **确定目标环境**

   按照 `ldc-deploy` skill 中的环境处理逻辑：
   - `$ARGUMENTS` 为 `test` → 测试环境
   - `$ARGUMENTS` 为 `prod` → 生产环境
   - `$ARGUMENTS` 为空 → 使用 AskUserQuestion 让用户选择

4. **执行构建**

   ```bash
   ldc build <appId>
   ```

   其中 `<appId>` 根据目标环境从 `.claude/deploy.json` 中读取对应的 `apps.test.appId` 或 `apps.prod.appId`。

   设置 `timeout: 600000`（10 分钟）

   `ldc build` 会交互式选择分支和 commit，透传给 ldc 的终端 UI。

5. **展示结果**

   - 成功：展示构建摘要，提示"构建完成，未提交发布申请"，输出 cloudUrl
   - 失败：提示构建失败，输出 cloudUrl 供用户前往未来云查看构建详情

**护栏**
- 仅执行构建，不提交发布申请
- 不执行 `ldc review` 审批操作
- 不执行 `ldc logout`
