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

3. **执行登录**
   - `Bash: ldc login`（timeout: 120000）
   - 终端会显示 ASCII 二维码，用户用手机扫码
   - 等待登录完成，输出结果

## 备选方案

如果 `ldc login` 在 Bash 工具中无法正常工作（交互式提示卡住），提示用户：
> 请在终端中手动执行 `ldc login` 完成扫码登录。

## 安全约束

- 不执行 `ldc logout`
