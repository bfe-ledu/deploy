---
name: "status"
description: 查看项目部署状态和最近发布记录
disable-model-invocation: true
category: Deploy
tags: [deploy, status, ldc]
---

查看项目的部署状态和最近发布记录。

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
   - 不存在则提示 "运行 `/ldc:init` 初始化配置" 并中止

3. **确定目标环境**

   按照 `ldc-deploy` skill 中的环境处理逻辑：
   - `$ARGUMENTS` 为 `test` → 测试环境
   - `$ARGUMENTS` 为 `prod` → 生产环境
   - `$ARGUMENTS` 为空 → 使用 AskUserQuestion 让用户选择

4. **查询状态**

   ```bash
   ldc deploy list <appId>
   ```

   其中 `<appId>` 根据目标环境从 `.claude/deploy.json` 中读取。

   设置 `timeout: 120000`（2 分钟）

5. **展示结果**

   - 成功：展示最近的发布记录列表（版本、状态、时间、操作人）
   - 输出 cloudUrl 供用户前往未来云查看更多详情
   - 失败：展示错误信息

**护栏**
- 只读操作，不执行任何修改
- 不执行 `ldc logout`
