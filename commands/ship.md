---
name: "Ship"
description: 一键构建并发布项目到未来云（测试/生产环境）
category: Deploy
tags: [deploy, build, ship, ldc]
---

一键构建并发布项目到未来云平台。

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

4. **生产环境确认**

   如果目标环境为 `prod`，**必须**使用 AskUserQuestion 进行二次确认：
   - 展示项目名称和目标环境
   - 用户确认后才继续执行

5. **执行 ship**

   根据环境执行对应命令：

   **测试环境：**
   ```bash
   ldc ship <test-appId> -b test
   ```
   设置 `timeout: 600000`（10 分钟）

   **生产环境：**
   ```bash
   ldc ship <prod-appId>
   ```
   设置 `timeout: 600000`（10 分钟）

   > **分支处理：** 测试环境默认使用 `-b test`；生产环境不指定分支，透传给 ldc 的交互式 UI 让用户选择。

   其中 `<test-appId>` 和 `<prod-appId>` 从 `.claude/deploy.json` 的 `apps.test.appId` 和 `apps.prod.appId` 读取。

6. **展示结果**

   - 成功：展示构建摘要（项目、环境、分支、commit），并输出未来云管理页链接（从配置中的 `cloudUrl` 读取）
   - 失败：提示构建失败，输出 cloudUrl 供用户前往未来云查看构建详情
   - 如需审批（qa_audit=1）：提示等待审批，并告知后续执行 `/deploy publish`

**护栏**
- 生产环境发布前**必须**二次确认
- 不执行 `ldc review` 审批操作
- 不执行 `ldc logout`
