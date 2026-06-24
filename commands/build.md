---
name: "Build"
description: 仅构建项目（打包），不提交发布申请
category: Deploy
tags: [deploy, build, ldc]
---

仅构建项目，不提交发布申请。适合提前验证构建是否通过。

**输入**: `$ARGUMENTS` 可以是环境标识 `test` 或 `prod`。如果为空则交互式选择。

## 编排流程

1. **前置检查**
   - `Bash: which ldc` — 未安装提示安装命令
   - `Bash: ldc whoami` — 未登录提示 `/login`

2. **读取项目配置**
   - `Read: .ldc.json`
   - 不存在 → 提示执行 `/init` 并结束

3. **确定目标环境**
   - `$ARGUMENTS` 包含 `test` → 环境为 test
   - `$ARGUMENTS` 包含 `prod` → 环境为 prod
   - `$ARGUMENTS` 包含 `pre` → 环境为 pre
   - `$ARGUMENTS` 为空 → `AskUserQuestion` 选择环境：
     - 选项：`test`（测试环境）、`prod`（生产环境）、`pre`（预发环境）

4. **选择版本方式**
   - `AskUserQuestion`：
     - 问题："选择版本方式？"
     - 选项："指定分支"、"指定 tag"

5. **捕获分支/tag 列表**
   - 使用 `expect` 启动 `ldc build <appId>`，自动回答前两步（确认"是"、选择版本方式）
   - 到达分支/tag 列表界面时，捕获显示的选项列表（解析 ANSI 输出提取名称）
   - 捕获完成后发送 Ctrl+C 退出进程
   - expect 脚本参考：
     ```bash
     expect -c '
     log_user 0
     set timeout 15
     spawn ldc build <appId>
     expect "确认部署本项目"
     sleep 0.3
     send "\r"
     expect "选择版本方式"
     sleep 0.3
     # 如果选分支：send "\x1b\[B" 然后 send "\r"
     # 如果选tag：直接 send "\r"
     send "<根据用户选择发送按键>\r"
     sleep 2
     expect -re ".+"
     puts $expect_out(buffer)
     send "\x03"
     expect eof
     ' 2>&1 | strings | grep -E "^  |❯"
     ```
   - 从输出中解析出分支/tag 名称列表（去除 ANSI 转义、`❯` 标记等）

6. **用户选择分支/tag**
   - `AskUserQuestion`：
     - 问题："选择要构建的分支/tag？"
     - 选项：从上一步捕获的列表中取前 3 个（显示名称）
     - 最后一个选项："手动输入"（如果用户选择此项，追问输入具体名称）

7. **捕获 commit 列表**
   - 再次使用 `expect` 启动 `ldc build <appId>`
   - 自动回答：确认"是" → 选择版本方式 → 输入分支/tag 名称并选择
   - 到达 commit 列表界面时，捕获显示的 commit 列表
   - 捕获完成后发送 Ctrl+C 退出进程
   - 从输出中解析 commit 列表（格式：`<hash> - <message>`）

8. **用户选择 commit**
   - `AskUserQuestion`：
     - 问题："选择要构建的 commit？"
     - 选项：从捕获的 commit 列表中取前 3 个（显示 hash 缩写 + 提交信息）
     - 默认推荐第一个（最新的）

9. **执行构建**
   - 使用 `expect` 启动 `ldc build <appId>`，自动完成全部交互：
     - 确认部署 → 回车（选"是"）
     - 选择版本方式 → 根据步骤 4 的选择发送按键
     - 输入分支/tag 名称 → 输入用户选择的名称并回车确认
     - 选择 commit → 根据用户选择发送对应次数的下箭头后回车
   - 设置 `timeout: 600000`（10 分钟）
   - 输出构建进度和结果

10. **展示结果**
    - 成功：展示构建摘要，提示"构建完成，未提交发布申请"
    - 失败：提示构建失败原因

## expect 交互按键对照

| ldc 步骤 | 默认选中 | 选择方式 |
|---------|---------|---------|
| 确认部署本项目？ | ❯ 是 | 直接回车 |
| 选择版本方式 | ❯ 指定 tag | 选分支需先按 ↓ 再回车 |
| 选择分支/tag | 搜索式列表 | 输入名称筛选后回车 |
| 选择 commit | 第 1 条 | 按 N 次 ↓ 后回车 |

## 安全约束

- 仅执行构建，不提交发布申请
- 不执行 `ldc review` 审批操作
- 不执行 `ldc logout`
