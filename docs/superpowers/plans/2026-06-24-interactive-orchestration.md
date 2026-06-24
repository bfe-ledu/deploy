# LDC Plugin 交互式编排 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 ldc 插件从"直接执行 CLI"升级为"Claude 智能编排"，在对话界面内通过 AskUserQuestion 等工具完成所有交互操作。

**Architecture:** 移除交互式命令的 `disable-model-invocation: true`，让 Claude 成为智能编排者。SKILL.md 作为核心参考手册提供编排模式，各 commands/*.md 定义具体的分步骤编排指令。

**Tech Stack:** Claude Code Plugin (markdown commands + skills), Bash tool, AskUserQuestion tool, Read tool, ldc CLI, git

## Global Constraints

- 只修改插件层（commands/*.md, skills/），不改动 ldc CLI 源码
- 保持现有的安全约束（prod 二次确认、rollback 二次确认）
- 保持现有的超时设置（ship/build: 600000ms, deploy: 120000ms, review/whoami/login: 60000ms）
- 不执行 `ldc logout`
- 保持 whoami, status, build 的 `disable-model-invocation: true`（直接执行模式）

---

## File Structure

| File | Responsibility | Change |
|------|---------------|--------|
| `skills/ldc-deploy/SKILL.md` | 核心参考手册：编排模式、错误处理、命令分类 | 增强 |
| `commands/login.md` | 扫码登录编排 | 改写 |
| `commands/ship.md` | 构建+发布编排（含分支选择） | 改写 |
| `commands/review.md` | 审批管理编排 | 改写 |
| `commands/rollback.md` | 回滚编排（含环境选择+二次确认） | 改写 |
| `commands/deploy.md` | 发布管理编排（含操作类型+环境选择） | 改写 |
| `commands/init.md` | 初始化配置编排 | 改写 |

---

### Task 1: 增强 SKILL.md 核心参考手册

**Files:**
- Modify: `skills/ldc-deploy/SKILL.md`

**Interfaces:**
- Consumes: 无（基础任务）
- Produces: 编排模式参考、错误处理表、命令分类定义（后续所有 commands/*.md 参考此文件）

- [ ] **Step 1: 改写 SKILL.md**

将 `skills/ldc-deploy/SKILL.md` 替换为以下内容：

```markdown
---
name: ldc-deploy
description: 通过 ledu-cloud-cli (ldc) 进行项目构建和部署。支持测试环境和生产环境的一键 ship、build、deploy、rollback、review 操作。
metadata:
  author: bfe-ledu
  version: "2.0"
---

# LDC Deploy — 未来云构建部署

通过 `ledu-cloud-cli`（命令 `ldc`）完成项目在未来云平台上的构建、发布、审批、回滚和状态查看。

---

## 命令分类

### AI 编排命令（Claude 智能编排，使用工具完成交互）
- `login` — 扫码登录
- `ship` — 一键构建+发布（含分支选择）
- `review` — 审批管理
- `rollback` — 回滚
- `deploy` — 发布管理
- `init` — 初始化配置

### 直接执行命令（disable-model-invocation: true，直接执行 CLI）
- `whoami` — 查看登录用户
- `status` — 查看部署状态
- `build` — 仅构建

---

## 前置检查

在执行任何 ldc 命令前，依次检查：

1. `Bash: which ldc` — 未安装则提示：
   ```
   npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/
   ```
2. `Bash: ldc whoami` — 未登录则提示执行 `/login`

---

## 项目配置

`.claude/deploy.json` 格式：

```json
{
  "projectName": "项目名称",
  "apps": {
    "test": { "appId": "xxx", "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=xxx" },
    "prod": { "appId": "yyy", "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=yyy" }
  }
}
```

使用 `Read: .claude/deploy.json` 读取。不存在时提示 `/init`。

---

## 编排模式

### 分支选择模式

用于 ship 命令选择部署分支：

1. `Bash: git branch -r --sort=-committerdate | head -20` — 获取最近活跃的远程分支
2. 解析输出，去除 `HEAD` 引用，取最近 3 个分支（去掉 `origin/` 前缀）
3. `AskUserQuestion`：展示 3 个分支选项 + "手动输入分支名"
4. 将选中分支传给 `ldc ship <appId> -b <branch>`

如果 `git branch -r` 无输出，直接让用户手动输入分支名。

### 环境选择模式

用于需要选择 test/prod 的命令：

1. 检查 `$ARGUMENTS`：如果包含 `test` 或 `prod`，直接使用
2. 未指定 → `AskUserQuestion`：选择 `test` 或 `prod`
3. 环境为 `prod` 时 → 必须 `AskUserQuestion` 二次确认

### 透传执行模式

用于 login/review 等自带交互式 UI 的 ldc 命令：

1. 直接 `Bash: ldc <command>`（设置合适的 timeout）
2. 将 stdout 原样展示给用户
3. 如果命令卡住或报错，提示用户在终端手动执行

---

## 超时设置

| 命令 | timeout |
|------|---------|
| `ldc ship` / `ldc build` | 600000 (10min) |
| `ldc deploy list/publish/rollback` | 120000 (2min) |
| `ldc login` | 120000 (2min，扫码需要时间) |
| `ldc review` / `ldc whoami` | 60000 (1min) |

---

## 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| ldc 未安装 | 提示 `npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/` |
| 未登录 | 提示执行 `/login` |
| deploy.json 缺失 | 提示执行 `/init` |
| 构建超时 | 提示检查 CI 状态，提供未来云链接 |
| 构建失败 | 展示错误日志，建议修复后重试 |
| 审批未通过 | 提示等待审批，建议 `/review` 查看 |
| git branch -r 无输出 | 让用户手动输入分支名 |

---

## 安全约束

- 生产环境发布前必须 `AskUserQuestion` 二次确认
- 回滚操作（任何环境）必须 `AskUserQuestion` 二次确认
- 不执行 `ldc logout`

---

## ldc 命令参考

| 命令 | 说明 |
|------|------|
| `ldc login` | 扫码登录 |
| `ldc whoami` | 查看登录用户 |
| `ldc ship [appId] [-b branch]` | 一键构建并发布 |
| `ldc build [appId]` | 仅构建 |
| `ldc deploy list [appId]` | 查询发布列表 |
| `ldc deploy publish [appId]` | 执行发布 |
| `ldc deploy rollback [appId]` | 回滚 |
| `ldc review` | 审批管理 |
```

- [ ] **Step 2: 提交**

```bash
git add skills/ldc-deploy/SKILL.md
git commit -m "feat: 增强 SKILL.md，添加编排模式和错误处理"
```

---

### Task 2: 改写 login.md

**Files:**
- Modify: `commands/login.md`

**Interfaces:**
- Consumes: SKILL.md 中的前置检查模式、透传执行模式
- Produces: login 命令的编排指令

- [ ] **Step 1: 改写 login.md**

将 `commands/login.md` 替换为以下内容：

```markdown
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
```

- [ ] **Step 2: 提交**

```bash
git add commands/login.md
git commit -m "feat: 改写 login.md，移除 disable-model-invocation，加入编排指令"
```

---

### Task 3: 改写 ship.md（核心）

**Files:**
- Modify: `commands/ship.md`

**Interfaces:**
- Consumes: SKILL.md 中的前置检查模式、分支选择模式、环境选择模式
- Produces: ship 命令的完整编排指令

- [ ] **Step 1: 改写 ship.md**

将 `commands/ship.md` 替换为以下内容：

```markdown
---
name: "Ship"
description: 一键构建并发布项目到未来云（测试/生产环境）
category: Deploy
tags: [deploy, build, ship, ldc]
---

一键构建并发布。`$ARGUMENTS` 为 `test` 或 `prod`，为空则交互选择。

## 编排流程

1. **前置检查**
   - `Bash: which ldc` — 未安装提示安装命令
   - `Bash: ldc whoami` — 未登录提示 `/login`

2. **读取项目配置**
   - `Read: .claude/deploy.json`
   - 不存在 → 提示执行 `/init` 并结束

3. **确定部署环境**
   - `$ARGUMENTS` 包含 `test` → 环境为 test，使用 `apps.test.appId`
   - `$ARGUMENTS` 包含 `prod` → 环境为 prod，使用 `apps.prod.appId`
   - `$ARGUMENTS` 为空 → `AskUserQuestion` 选择环境：
     - 选项：`test`（测试环境）、`prod`（生产环境）

4. **生产环境二次确认**
   - 环境为 `prod` → `AskUserQuestion`：
     - 问题："确认要部署到生产环境吗？"
     - 选项："确认部署"、"取消"

5. **选择分支**
   - `Bash: git branch -r --sort=-committerdate | head -20`
   - 解析输出，去除 `HEAD` 引用和 `origin/` 前缀，取最近 3 个分支
   - `AskUserQuestion`：
     - 问题："选择要部署的分支？"
     - 选项 1-3：最近 3 个分支（显示分支名 + 最近提交信息）
     - 选项 4："手动输入分支名"
   - 如果 `git branch -r` 无输出 → 让用户手动输入分支名

6. **执行构建发布**
   - test: `Bash: ldc ship <apps.test.appId> -b <branch>`（timeout: 600000）
   - prod: `Bash: ldc ship <apps.prod.appId> -b <branch>`（timeout: 600000）
   - 输出构建进度和结果

## 安全约束

- 不执行 `ldc review` / `ldc logout`
```

- [ ] **Step 2: 提交**

```bash
git add commands/ship.md
git commit -m "feat: 改写 ship.md，加入分支选择 AskUserQuestion 流程"
```

---

### Task 4: 改写 review.md

**Files:**
- Modify: `commands/review.md`

**Interfaces:**
- Consumes: SKILL.md 中的前置检查模式、透传执行模式
- Produces: review 命令的编排指令

- [ ] **Step 1: 改写 review.md**

将 `commands/review.md` 替换为以下内容：

```markdown
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
```

- [ ] **Step 2: 提交**

```bash
git add commands/review.md
git commit -m "feat: 改写 review.md，移除 disable-model-invocation，透传执行"
```

---

### Task 5: 改写 rollback.md

**Files:**
- Modify: `commands/rollback.md`

**Interfaces:**
- Consumes: SKILL.md 中的前置检查模式、环境选择模式
- Produces: rollback 命令的编排指令

- [ ] **Step 1: 改写 rollback.md**

将 `commands/rollback.md` 替换为以下内容：

```markdown
---
name: "Rollback"
description: 回滚到已发布版本的上一版本
category: Deploy
tags: [deploy, rollback, ldc]
---

回滚到上一发布版本。`$ARGUMENTS` 为 `test` 或 `prod`，为空则交互选择。

## 编排流程

1. **前置检查**
   - `Bash: which ldc` — 未安装提示安装命令
   - `Bash: ldc whoami` — 未登录提示 `/login`

2. **读取项目配置**
   - `Read: .claude/deploy.json`
   - 不存在 → 提示执行 `/init` 并结束

3. **确定回滚环境**
   - `$ARGUMENTS` 包含 `test` → 环境为 test，使用 `apps.test.appId`
   - `$ARGUMENTS` 包含 `prod` → 环境为 prod，使用 `apps.prod.appId`
   - `$ARGUMENTS` 为空 → `AskUserQuestion` 选择环境：
     - 选项："test"（测试环境）、"prod"（生产环境）

4. **二次确认（所有环境必须）**
   - `AskUserQuestion`：
     - 问题："确认要回滚 <环境名> 环境到上一版本吗？这是破坏性操作。"
     - 选项："确认回滚"、"取消"

5. **执行回滚**
   - `Bash: ldc deploy rollback <appId>`（timeout: 120000）
   - 输出回滚结果

## 安全约束

- 任何环境的回滚操作都必须二次确认
- 不执行 `ldc review` / `ldc logout`
```

- [ ] **Step 2: 提交**

```bash
git add commands/rollback.md
git commit -m "feat: 改写 rollback.md，加入环境选择和二次确认"
```

---

### Task 6: 改写 deploy.md

**Files:**
- Modify: `commands/deploy.md`

**Interfaces:**
- Consumes: SKILL.md 中的前置检查模式、环境选择模式
- Produces: deploy 命令的编排指令

- [ ] **Step 1: 改写 deploy.md**

将 `commands/deploy.md` 替换为以下内容：

```markdown
---
name: "Deploy"
description: 发布管理 — 查看待发布列表或执行发布
category: Deploy
tags: [deploy, publish, ldc]
---

发布管理。`$ARGUMENTS` 格式 `[action] [env]`，action 为 `list`（默认）或 `publish`，env 为 `test` 或 `prod`。

## 编排流程

1. **前置检查**
   - `Bash: which ldc` — 未安装提示安装命令
   - `Bash: ldc whoami` — 未登录提示 `/login`

2. **读取项目配置**
   - `Read: .claude/deploy.json`
   - 不存在 → 提示执行 `/init` 并结束

3. **确定操作类型**
   - `$ARGUMENTS` 包含 `list` → 操作为 list
   - `$ARGUMENTS` 包含 `publish` → 操作为 publish
   - 未指定 → `AskUserQuestion` 选择：
     - 选项："list"（查看待发布列表）、"publish"（执行发布）

4. **确定环境**
   - `$ARGUMENTS` 包含 `test` → 环境为 test，使用 `apps.test.appId`
   - `$ARGUMENTS` 包含 `prod` → 环境为 prod，使用 `apps.prod.appId`
   - 未指定 → `AskUserQuestion` 选择：
     - 选项："test"（测试环境）、"prod"（生产环境）

5. **生产环境发布二次确认**
   - 操作为 `publish` 且环境为 `prod` → `AskUserQuestion`：
     - 问题："确认要在生产环境执行发布吗？"
     - 选项："确认发布"、"取消"

6. **执行命令**
   - list: `Bash: ldc deploy list <appId>`（timeout: 120000）
   - publish: `Bash: ldc deploy publish <appId>`（timeout: 120000）
   - 输出结果

## 安全约束

- publish + prod 必须二次确认
- 不执行 `ldc review` / `ldc logout`
```

- [ ] **Step 2: 提交**

```bash
git add commands/deploy.md
git commit -m "feat: 改写 deploy.md，加入操作类型和环境选择"
```

---

### Task 7: 改写 init.md

**Files:**
- Modify: `commands/init.md`

**Interfaces:**
- Consumes: SKILL.md 中的项目配置格式
- Produces: init 命令的编排指令

- [ ] **Step 1: 改写 init.md**

将 `commands/init.md` 替换为以下内容：

```markdown
---
name: "Init"
description: 初始化项目的 .claude/deploy.json 部署配置
category: Deploy
tags: [deploy, init, config, ldc]
---

初始化 `.claude/deploy.json` 部署配置文件。

## 编排流程

1. **检查已有配置**
   - `Read: .claude/deploy.json`
   - 已存在 → 展示内容，`AskUserQuestion` 询问是否覆盖：
     - 选项："覆盖重新配置"、"保留现有配置"
     - 选择保留 → 结束

2. **收集配置信息**
   - `AskUserQuestion`：项目名称（默认使用当前目录名）
   - `AskUserQuestion`：测试环境 App ID
   - `AskUserQuestion`：生产环境 App ID（可选，留空跳过）

3. **写入配置文件**
   - 写入 `.claude/deploy.json`：

```json
{
  "projectName": "<项目名>",
  "apps": {
    "test": {
      "appId": "<test-appId>",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
    },
    "prod": {
      "appId": "<prod-appId>",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
    }
  }
}
```

   - 未提供生产 App ID 则不写 `apps.prod`
   - `cloudUrl` 中 `<appId>` 替换为实际值

4. **输出结果**
   - 展示写入的配置内容
   - 提示可以执行 `/ship test` 开始部署
```

- [ ] **Step 2: 提交**

```bash
git add commands/init.md
git commit -m "feat: 改写 init.md，移除 disable-model-invocation"
```

---

### Task 8: 集成验证

**Files:** 无文件变更，仅验证

**Interfaces:**
- Consumes: 所有改写后的 commands/*.md 和 skills/ldc-deploy/SKILL.md
- Produces: 验证报告

- [ ] **Step 1: 验证 whoami（直接执行命令未变）**

```bash
claude --plugin-dir . -p "/ldc:whoami"
```
Expected: 输出 ldc whoami 结果或提示安装

- [ ] **Step 2: 验证 login 编排**

```bash
claude --plugin-dir . -p "/ldc:login"
```
Expected: 按编排流程执行前置检查，如已登录则输出用户信息

- [ ] **Step 3: 验证 ship 分支选择**

```bash
claude --plugin-dir . -p "/ldc:ship test"
```
Expected: 前置检查 → 读取配置 → 获取分支列表 → AskUserQuestion 选择分支

- [ ] **Step 4: 验证 review 透传**

```bash
claude --plugin-dir . -p "/ldc:review"
```
Expected: 前置检查 → 透传 ldc review 输出

- [ ] **Step 5: 验证 deploy 操作选择**

```bash
claude --plugin-dir . -p "/ldc:deploy"
```
Expected: 前置检查 → AskUserQuestion 选择操作类型和环境

- [ ] **Step 6: 验证 init 配置收集**

```bash
claude --plugin-dir . -p "/ldc:init"
```
Expected: AskUserQuestion 收集配置信息 → 写入 deploy.json

- [ ] **Step 7: 最终提交**

```bash
git log --oneline -10
```
确认所有 commit 正确，准备推送。
