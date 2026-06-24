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

2. **运行登录脚本**
   - `Bash: node $(dirname "$(find ~/.claude/plugins -name qr-login.mjs -path "*/deploy/*" 2>/dev/null | head -1)")/qr-login.mjs`（timeout: 150000）
   - 脚本会输出结构化状态信息

3. **处理输出**
   - 解析 stdout 中的 `STATUS:` 和 `MESSAGE:` 行
   - `STATUS:OK` → 输出 MESSAGE，结束
   - `STATUS:NEED_QR` → 进入步骤 4
   - `STATUS:ERROR` → 输出错误信息，结束

4. **显示二维码**
   - 从 stdout 解析 `QR_PNG:<path>` 获取 PNG 路径
   - `Read: <QR_PNG 路径>` — 在对话中内联显示二维码图片
   - 告诉用户："请使用知音楼好未来主体扫描二维码完成登录"
   - 等待脚本完成（扫码后脚本会自动保存 token 并输出 STATUS:OK）

## 备选方案

如果辅助脚本运行失败（Node.js 环境问题、playwright 不可用等），回退到：
- `Bash: ldc login`（timeout: 120000）
- 如果终端二维码显示不完整，提示用户手动在终端执行 `ldc login`

## 安全约束

- 不执行 `ldc logout`
