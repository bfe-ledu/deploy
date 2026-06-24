---
name: "Login"
description: 扫码登录 ledu-cloud-cli
category: Deploy
tags: [deploy, login, ldc, auth]
---

扫码登录未来云。

## 编排流程

1. **检查 ldc 安装**
   - `Bash: which ldc`
   - 未安装 → 输出安装命令并结束：
     ```
     npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/
     ```

2. **检查登录状态**
   - `Bash: ldc whoami`
   - 已登录 → 输出用户信息并结束

3. **执行登录（后台运行，捕获输出到文件）**
   - `Bash(run_in_background: true): ldc login 2>&1 | tee /tmp/ldc-login-output.txt`（timeout: 120000）
   - 等待 3 秒让二维码生成完毕

4. **显示完整二维码**
   - `Read: /tmp/ldc-login-output.txt` — 在对话中展示完整的 ASCII 二维码
   - 告诉用户："请使用知音楼好未来主体扫描上方二维码"
   - 等待后台任务完成（用户扫码后 ldc 会自动完成登录并退出）

5. **确认登录**
   - 后台任务完成后，`Bash: ldc whoami` 验证登录成功

## 安全约束

- 不执行 `ldc logout`
