---
name: "Login"
description: 扫码登录 ledu-cloud-cli
category: Deploy
tags: [deploy, login, ldc, auth]
---

登录 ledu-cloud-cli，获取部署操作所需的凭证。

**输入**: 无参数

**步骤**

1. **检查 ldc 是否安装**

   按照 `ldc-deploy` skill 中的前置检查步骤 1：
   - 执行 `which ldc`
   - 未安装 → AskUserQuestion 询问是否自动安装
     - 同意 → 执行 `npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/`
     - 拒绝 → 中止

2. **检查登录状态**

   执行 `ldc whoami`：
   - 已登录 → 展示用户信息，提示"已登录，无需重复操作"，结束

3. **执行登录**

   ```bash
   ldc login
   ```
   设置 `timeout: 60000`（1 分钟）

4. **验证登录**

   执行 `ldc whoami` 验证登录成功，展示用户信息。

**护栏**
- 不执行 `ldc logout`
