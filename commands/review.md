---
name: "Review"
description: 批量审批项目发布和团队申请
category: Deploy
tags: [deploy, review, approve, ldc]
---

执行审批管理。不需要项目配置。

## 编排流程

1. **前置检查**
   - `Bash: which ldc` — 未安装提示安装命令
   - `Bash: ldc whoami` — 未登录提示 `/login`

2. **执行审批**
   - `Bash: ldc review`（timeout: 60000）
   - 透传输出：ldc 自带交互式审批 UI，直接展示结果

## 备选方案

如果 `ldc review` 在 Bash 工具中无法正常工作，提示用户：
> 请在终端中手动执行 `ldc review` 完成审批操作。

## 安全约束

- 不执行 `ldc logout`
