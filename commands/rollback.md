---
name: "Rollback"
description: 回滚到已发布版本的上一版本
disable-model-invocation: true
category: Deploy
tags: [deploy, rollback, ldc]
---

回滚到已发布版本的上一版本。**这是破坏性操作，无论测试/生产环境都需要二次确认。**

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

4. **二次确认**

   **必须**使用 AskUserQuestion 进行二次确认（无论测试/生产环境）：
   - 展示项目名称、目标环境
   - 明确提示"回滚是破坏性操作，将恢复到上一发布版本"
   - 用户确认后才继续执行

5. **执行回滚**

   ```bash
   ldc deploy rollback <appId>
   ```

   其中 `<appId>` 根据目标环境从 `.claude/deploy.json` 中读取。

   设置 `timeout: 120000`（2 分钟）

6. **展示结果**

   - 成功：展示回滚结果，输出 cloudUrl
   - 失败：展示错误信息和排查建议

**护栏**
- **任何环境**回滚前都必须二次确认
- 不执行 `ldc review` 审批操作
- 不执行 `ldc logout`
