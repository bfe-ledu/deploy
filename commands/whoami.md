---
name: "Whoami"
description: 查看当前 ldc 登录用户信息
disable-model-invocation: true
category: Deploy
tags: [deploy, whoami, ldc, auth]
---

查看当前 ledu-cloud-cli 的登录用户信息。

**输入**: 无参数

**步骤**

1. **检查 ldc 是否安装**

   按照 `ldc` skill 中的前置检查步骤 1：
   - 执行 `which ldc`
   - 未安装 → AskUserQuestion 询问是否自动安装
     - 同意 → 执行 `npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/`
     - 拒绝 → 中止

2. **查看用户信息**

   ```bash
   ldc whoami
   ```
   设置 `timeout: 60000`（1 分钟）

3. **展示结果**

   - 已登录 → 展示用户信息
   - 未登录 → 提示"未登录，请执行 `/login` 登录"
