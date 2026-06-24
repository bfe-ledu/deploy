# LDC Plugin 交互式编排设计

> 将 ldc 插件从"直接执行 CLI"升级为"Claude 智能编排"，在对话界面内完成所有交互操作。

## 背景

当前 ldc 插件使用 `disable-model-invocation: true`，Claude 直接执行 CLI 命令。这导致：
- `ldc login` 的交互式二维码在非交互终端中可能卡住
- `ldc ship` 的分支选择器（inquirer）在 Claude Code Bash 工具中无法正常工作
- 用户体验不够流畅，需要跳出对话窗口

## 目标

1. 移除交互式命令的 `disable-model-invocation: true`
2. 让 Claude 成为智能编排者，使用内置工具（Bash、AskUserQuestion、Read）完成交互
3. 保持简单命令（whoami、status、build）的直接执行模式

## 设计

### 整体架构

```
当前模式（disable-model-invocation: true）:
  用户 → /ship → Claude 直接执行 `ldc ship <appId>` → CLI 交互式 UI（在 Bash 中卡住）

目标模式（移除 disable-model-invocation）:
  用户 → /ship → Claude 读取指令 → 分步骤编排：
    1. Bash: 前置检查（which ldc, ldc whoami）
    2. Bash: 获取数据（分支列表等）
    3. AskUserQuestion: 用户选择
    4. Bash: 执行 `ldc ship <appId> -b <branch>`
    5. 输出结果
```

### 文件变更范围

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `commands/login.md` | 改写 | 移除 disable-model-invocation，加入编排指令 |
| `commands/ship.md` | 改写 | 同上，加入分支获取 + AskUserQuestion 流程 |
| `commands/review.md` | 改写 | 同上，加入审批列表展示 + 选择流程 |
| `commands/rollback.md` | 改写 | 同上，加入版本选择流程 |
| `commands/deploy.md` | 改写 | 同上 |
| `skills/ldc-deploy/SKILL.md` | 增强 | 加入详细的编排模式、API 参考、错误处理 |
| `commands/whoami.md` | 不变 | 保持直接执行 |
| `commands/status.md` | 不变 | 保持直接执行 |
| `commands/build.md` | 不变 | 保持直接执行 |
| `commands/init.md` | 改写 | 移除 disable-model-invocation，保留 AskUserQuestion 流程 |

### Login 流程

**目标：** 用户在 Claude Code 对话中看到二维码并完成扫码登录。

**编排流程：**

1. `Bash: which ldc` — 未安装则提示安装命令，结束
2. `Bash: ldc whoami` — 已登录则输出用户信息，结束
3. `Bash: ldc login`（timeout: 120000）— 直接执行，ldc 在终端输出 ASCII 二维码，用户扫码后自动完成登录

**关键决策：** `ldc login` 本身已处理二维码展示和轮询等待，Claude 只需直接执行并透传输出。终端中的 ASCII 二维码用户可以直接用手机扫描。

**备选方案：** 如果 Claude Code 的 Bash 工具不支持 ldc login 的交互式流程（如 inquirer 提示无法正常工作），则改为：
1. 使用 `npx qrcode-terminal` 或 Node.js 脚本在终端生成二维码
2. 或提示用户手动在终端执行 `ldc login`

### Ship 流程（核心）

**目标：** 用户通过 AskUserQuestion 选择分支，Claude 执行 ship 并实时输出构建进度。

**编排流程：**

1. `Bash: which ldc` — 未安装提示安装
2. `Bash: ldc whoami` — 未登录提示 /login
3. `Read: .claude/deploy.json` — 不存在提示 /init
4. 确定环境（test/prod）：$ARGUMENTS 为 test/prod 则直接使用，为空则 `AskUserQuestion` 选择
5. prod 环境 → `AskUserQuestion` 二次确认
6. `Bash: git branch -r --sort=-committerdate | head -20` — 获取最近的远程分支列表
7. `AskUserQuestion` — 展示最近 3 个分支 + "手动输入分支名"选项
8. `Bash: ldc ship <appId> -b <branch>`（timeout: 600000）— 执行并输出构建进度

**分支获取策略：** 使用 `git branch -r --sort=-committerdate | head -20` 获取最近活跃的远程分支。
- 不需要调用云平台 API（不依赖额外认证）
- 不需要修改 ldc CLI
- 分支按最近提交时间排序，最常用的在前面
- 用户也可以手动输入分支名

### Review 流程

**编排流程：**

1. 前置检查（which ldc, ldc whoami）
2. `Bash: ldc review`（timeout: 60000）— 直接执行，ldc 自带交互式审批 UI，透传输出

### Rollback 流程

**编排流程：**

1. 前置检查
2. `Read: .claude/deploy.json`
3. 确定环境 → `AskUserQuestion`（如未指定）
4. `AskUserQuestion` — 二次确认回滚操作
5. `Bash: ldc deploy rollback <appId>`（timeout: 120000）

### Deploy 流程

**编排流程：**

1. 前置检查
2. `Read: .claude/deploy.json`
3. 确定操作类型（list/publish）→ `AskUserQuestion`（如未指定）
4. 确定环境 → `AskUserQuestion`（如未指定）
5. publish 且 prod → `AskUserQuestion` 二次确认
6. `Bash: ldc deploy <action> <appId>`（timeout: 120000）

### SKILL.md 增强

#### 编排模式参考

**分支选择模式：**
1. `Bash(git branch -r --sort=-committerdate | head -20)` 获取分支
2. 解析输出，取最近 3 个分支
3. `AskUserQuestion` 展示选项 + "手动输入"选项
4. 将选中分支传给后续命令

**环境选择模式：**
1. 检查 $ARGUMENTS 是否指定了 test/prod
2. 未指定 → `AskUserQuestion` 选择环境
3. prod → 必须 `AskUserQuestion` 二次确认

**透传执行模式：**
用于 login/review 等自带交互式 UI 的 ldc 命令：
1. 直接 `Bash(ldc <command>)`
2. 将 stdout 原样展示给用户

#### 错误处理表

| 错误场景 | 处理方式 |
|---------|---------|
| ldc 未安装 | 提示 `npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/` |
| 未登录 | 提示执行 `/login` |
| deploy.json 缺失 | 提示执行 `/init` |
| 构建超时 | 提示检查 CI 状态 |
| 构建失败 | 展示错误日志，建议修复后重试 |
| 审批未通过 | 提示等待审批，建议 `/review` 查看 |

#### 命令分类

- **AI 编排命令**（移除 disable-model-invocation）：login, ship, review, rollback, deploy, init
- **直接执行命令**（保持 disable-model-invocation: true）：whoami, status, build

## 约束

- 只修改插件层（commands/*.md, skills/），不改动 ldc CLI 源码
- 保持现有的安全约束（prod 二次确认、rollback 二次确认）
- 保持现有的超时设置
- 不执行 `ldc logout`

## 风险与假设

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| Bash 工具不支持交互式 CLI | Login/Review 透传失败 | 增加备选方案：提示用户手动执行或改用非交互模式 |
| AI 不按指令编排 | 流程混乱 | SKILL.md 提供详细示例，测试验证 |
| git branch -r 无输出 | Ship 无法获取分支 | 回退到让用户手动输入分支名 |

## 验证计划

实现完成后，按以下步骤验证：

1. `claude --plugin-dir . -p "/ldc:whoami"` — 验证直接执行命令正常
2. `claude --plugin-dir . -p "/ldc:login"` — 验证登录流程，观察二维码输出
3. `claude --plugin-dir . -p "/ldc:ship test"` — 验证分支选择 AskUserQuestion
4. `claude --plugin-dir . -p "/ldc:review"` — 验证审批流程透传
