---
name: "review"
description: 批量审批项目发布和团队申请
disable-model-invocation: true
category: Deploy
tags: [deploy, review, approve, ldc]
---

查看和批量审批项目发布申请和团队申请。

**输入**: 无参数

**步骤**

1. **前置检查**

   按照 `ldc-deploy` skill 中的前置检查流程：
   - 检查 `ldc` 是否安装（`which ldc`），未安装则询问是否自动安装
   - 检查登录状态（`ldc whoami`）
   - 未通过则按 skill 中的提示处理并中止

   > 注意：`/ldc:review` 不需要项目配置（`.claude/deploy.json`），因为审批操作与具体项目无关。

2. **执行审批**

   ```bash
   ldc review
   ```
   设置 `timeout: 60000`（1 分钟）

   `ldc review` 是交互式命令，流程：
   1. 选择审批类型（项目发布 / 团队申请），显示待审批数量
   2. 选择操作（通过 / 拒绝）
   3. 多选待审批项（空格多选，a 全选）
   4. 确认后批量执行，实时展示进度

   Claude Code 会在终端中直接运行此命令，用户可以进行交互操作。

3. **展示结果**

   审批完成后展示操作结果摘要。

**护栏**
- 审批操作通过 ldc 的交互式 UI 进行，由用户自主确认
- 不执行 `ldc logout`
