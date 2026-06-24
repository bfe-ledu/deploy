---
name: "Init"
description: 初始化项目的 .ldc.json 部署配置
category: Deploy
tags: [deploy, init, config, ldc]
---

初始化 `.ldc.json` 部署配置文件。

## 编排流程

1. **检查 ldc 安装**
   - `Bash: which ldc`
   - 未安装 → 提示安装命令并结束：
     ```
     npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/
     ```

2. **检查已有配置**
   - `Read: .ldc.json`
   - 已存在 → 展示内容，`AskUserQuestion` 询问是否覆盖：
     - 选项："覆盖重新配置"、"保留现有配置"
     - 选择保留 → 结束

3. **收集配置信息**
   - `AskUserQuestion`：测试环境 App ID（从未来云页面 URL `?id=xxx` 中获取，也可直接粘贴 URL）
   - `AskUserQuestion`：生产环境 App ID（可选，留空跳过）
   - `AskUserQuestion`：预发环境 App ID（可选，留空跳过）

4. **执行初始化**
   - 根据收集的信息拼接命令：
     - 仅 test: `Bash: ldc init --test <testAppId>`
     - test + prod: `Bash: ldc init --test <testAppId> --prod <prodAppId>`
     - test + prod + pre: `Bash: ldc init --test <testAppId> --prod <prodAppId> --pre <preAppId>`
   - `ldc init` 会将配置保存到项目根目录 `.ldc.json`

5. **输出结果**
   - 展示 `.ldc.json` 内容
   - 提示可以执行 `/ship test` 开始部署
