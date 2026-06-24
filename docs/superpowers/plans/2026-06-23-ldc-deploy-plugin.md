# LDC Deploy Plugin 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建一个纯 Skill + Commands 的 Claude Code Plugin，让团队通过斜杠命令一键完成未来云的构建、发布、审批和回滚操作。

**Architecture:** 零代码架构 — 1 个 SKILL.md 承载共享逻辑（前置检查、配置读取、环境选择、安全约束），9 个 commands/*.md 各对应一个斜杠命令，通过引用 Skill 中的流程来执行。所有命令最终调用 `ldc` CLI 完成实际操作。

**Tech Stack:** Claude Code Plugin (Markdown-only), ledu-cloud-cli (ldc), Git

## Global Constraints

- 纯 Markdown 文件，不使用任何编程语言或第三方依赖
- 命令文件使用 YAML frontmatter: `name`, `description`, `category`, `tags`
- 所有命令引用 `ldc` skill 的共享流程，不重复定义逻辑
- 生产环境操作必须 AskUserQuestion 二次确认
- 回滚操作无论环境必须二次确认
- 不自动执行 `ldc logout`
- 超时策略：ship/build 600000ms, deploy/rollback/status 120000ms, review/whoami/login 60000ms
- 安装包名：`ledu-cloud-cli`，源：`https://registry.npmjs.org/`

---

## File Structure

| 文件路径 | 职责 |
|----------|------|
| `.claude-plugin/plugin.json` | 插件元信息（已存在，需更新） |
| `skills/ldc/SKILL.md` | 核心技能：前置检查、配置读取、环境选择、安全约束、结果展示 |
| `commands/init.md` | /init — 初始化 .claude/deploy.json |
| `commands/login.md` | /login — 扫码登录 |
| `commands/whoami.md` | /whoami — 查看登录用户 |
| `commands/ship.md` | /ship [test\|prod] — 一键构建+发布 |
| `commands/build.md` | /build [test\|prod] — 仅构建 |
| `commands/deploy.md` | /deploy [list\|publish] [test\|prod] — 发布管理 |
| `commands/rollback.md` | /rollback [test\|prod] — 回滚 |
| `commands/review.md` | /review — 批量审批 |
| `commands/status.md` | /status [test\|prod] — 查看部署状态 |
| `README.md` | 使用说明（已存在，需重写） |

---

### Task 1: 更新 plugin.json 和创建 Skill 文件

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Create: `skills/ldc/SKILL.md`

**Interfaces:**
- Produces: Skill 文件中定义的共享流程（前置检查、配置读取、环境选择、安全约束），所有后续 command 文件通过 "按照 `ldc` skill 中的 XXX 流程" 引用

- [ ] **Step 1: 更新 plugin.json**

覆盖 `.claude-plugin/plugin.json`:

```json
{
  "name": "ldc",
  "description": "未来云一键部署 — 通过 ldc CLI 完成构建、发布、审批、回滚",
  "version": "1.0.0",
  "author": { "name": "bfe-ledu", "email": "p_zhaoxin10@ledupeiyou.com" },
  "homepage": "https://github.com/bfe-ledu/deploy",
  "repository": "https://github.com/bfe-ledu/deploy",
  "license": "MIT",
  "keywords": ["cloud", "deploy", "ldc", "ship", "build", "review", "rollback"]
}
```

- [ ] **Step 2: 创建 skills/ldc/SKILL.md**

```markdown
---
name: ldc
description: 通过 ledu-cloud-cli (ldc) 进行项目构建和部署。支持测试环境和生产环境的一键 ship、build、deploy、rollback、review 操作。
metadata:
  author: bfe-ledu
  version: "1.0"
---

# LDC Deploy — 未来云构建部署

通过 `ledu-cloud-cli`（命令 `ldc`）完成项目在未来云平台上的构建、发布、审批、回滚和状态查看。

---

## 前置检查

在执行任何 ldc 命令前，**必须**依次检查：

### 1. 检查 ldc 是否安装

```bash
which ldc
```

- 如果返回路径 → 已安装，继续
- 如果为空 → 未安装，使用 AskUserQuestion 询问用户是否同意自动安装：
  - 用户同意 → 执行：
    ```bash
    npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/
    ```
    安装完成后继续
  - 用户拒绝 → 中止执行

### 2. 检查登录状态

```bash
ldc whoami
```

- 如果返回用户信息 → 已登录，继续
- 如果报错或提示未登录 → 提示用户执行 `/login` 命令，中止执行

---

## 项目配置读取

每个项目通过 `.claude/deploy.json` 配置部署信息：

```json
{
  "projectName": "项目名称",
  "apps": {
    "test": {
      "appId": "测试环境 App ID",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
    },
    "prod": {
      "appId": "生产环境 App ID",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
    }
  }
}
```

### 读取流程

1. 查找当前项目根目录的 `.claude/deploy.json`
2. 解析 JSON 获取 `apps` 对象
3. 根据目标环境（test/prod）获取对应的 `appId` 和 `cloudUrl`

### 配置不存在时

如果 `.claude/deploy.json` 不存在，提示用户 "运行 `/init` 初始化项目配置" 并中止执行。

---

## 环境处理

| 环境 | 标识 | App ID 来源 | 默认分支 | 额外约束 |
|------|------|-------------|----------|----------|
| 测试环境 | `test` | `apps.test.appId` | `-b test` | 无 |
| 生产环境 | `prod` | `apps.prod.appId` | 透传给 ldc 交互选择 | **发布前必须二次确认** |

### 环境选择逻辑

1. 如果命令参数指定了环境 → 直接使用
2. 如果未指定 → 使用 AskUserQuestion 让用户选择 test 或 prod

---

## 执行策略

### 超时设置

- `ldc ship` 和 `ldc build`：构建过程可能需要较长时间，设置 `timeout: 600000`（10 分钟）
- `ldc deploy list`、`ldc deploy publish`、`ldc deploy rollback`：设置 `timeout: 120000`（2 分钟）
- `ldc review`、`ldc whoami`、`ldc login`：设置 `timeout: 60000`（1 分钟）

### 输出展示

- 实时展示命令执行输出
- 构建成功时展示项目名、环境、分支、commit 信息
- 构建失败时提示失败并输出 cloudUrl，引导用户前往未来云查看构建详情

### 安全约束

- **生产环境（prod）发布前必须使用 AskUserQuestion 进行二次确认**
- **回滚操作（任何环境）必须使用 AskUserQuestion 进行二次确认**
- 不自动执行 `ldc review` 审批操作（由 /review 命令专门处理）
- 不修改登录凭证（不执行 `ldc logout`）

---

## ldc 命令参考

### 账号管理

| 命令 | 说明 |
|------|------|
| `ldc login` | 扫码登录（使用知音楼好未来主体） |
| `ldc logout` | 退出登录，清空本地 token |
| `ldc whoami` | 查看当前登录用户信息 |

### 构建发布

| 命令 | 别名 | 说明 |
|------|------|------|
| `ldc ship [appId]` | `s` | 一键构建并发布 |
| `ldc ship -b <branch>` | | 指定分支部署 |
| `ldc build [appId]` | `b` | 仅打包构建，不发布 |

### 部署管理

| 命令 | 别名 | 说明 |
|------|------|------|
| `ldc deploy apply [appId]` | `a` | 提交发布申请 |
| `ldc deploy list [appId]` | `ls` | 查询发布申请列表 |
| `ldc deploy publish [appId]` | `p` | 执行发布 |
| `ldc deploy rollback [appId]` | `rb` | 回滚到已发布版本的上一版本 |

### 审批管理

| 命令 | 别名 | 说明 |
|------|------|------|
| `ldc review` | `r` | 审批管理（项目发布/团队申请） |

### 未来云地址

项目管理页：`https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>`

---

## 常见工作流

### 测试环境日常部署（推荐）

```bash
ldc ship <appId> -b test
```

指定 test 分支，自动取最新 commit，一键完成构建 + 发布。

### 研发自测项目（qa_audit=0）

```bash
ldc ship <appId>
```

全自动：选择分支 → 构建 → 提交申请 → 自动发布。

### 需要审批的项目（qa_audit=1）

```bash
# 1. 构建 + 提交申请
ldc ship <appId>

# 2. 审批通过后，执行发布
ldc deploy publish <appId>
```

---

## 环境要求

- Node.js >= 18
- macOS（扫码登录依赖系统浏览器 profile）
```

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json skills/
git commit -m "feat: 添加 plugin.json 和 ldc skill 核心文件"
```

---

### Task 2: 创建基础命令（init / login / whoami）

**Files:**
- Create: `commands/init.md`
- Create: `commands/login.md`
- Create: `commands/whoami.md`

**Interfaces:**
- Consumes: `ldc` skill 中的前置检查流程
- Produces: `/init` 命令生成 `.claude/deploy.json`，供其他命令读取

- [ ] **Step 1: 创建 commands/init.md**

```markdown
---
name: "Init"
description: 初始化项目的 .claude/deploy.json 部署配置
category: Deploy
tags: [deploy, init, config, ldc]
---

初始化项目的部署配置文件 `.claude/deploy.json`。

**输入**: 无参数

**步骤**

1. **检查配置是否已存在**

   读取当前项目根目录的 `.claude/deploy.json`：
   - 已存在 → 展示当前配置内容，使用 AskUserQuestion 询问是否覆盖
     - 用户选择不覆盖 → 中止
   - 不存在 → 继续

2. **收集项目信息**

   使用 AskUserQuestion 依次收集：
   - 项目名称（默认使用当前目录名）
   - 测试环境 App ID（从未来云项目管理页 URL 中获取）
   - 生产环境 App ID（可选，输入 "无" 则跳过）

3. **生成配置文件**

   创建 `.claude/deploy.json`，内容格式：

   ```json
   {
     "projectName": "<用户输入的项目名>",
     "apps": {
       "test": {
         "appId": "<用户输入的测试 App ID>",
         "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
       },
       "prod": {
         "appId": "<用户输入的生产 App ID>",
         "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
       }
     }
   }
   ```

   如果用户未提供生产 App ID，则 `apps.prod` 部分不写入。

4. **展示结果**

   - 输出配置摘要（项目名、各环境 appId）
   - 提示 "配置已生成，现在可以使用 `/ship test` 部署测试环境"

**护栏**
- 不自动覆盖已有配置
- cloudUrl 中的 `<appId>` 替换为实际 App ID
```

- [ ] **Step 2: 创建 commands/login.md**

```markdown
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

   按照 `ldc` skill 中的前置检查步骤 1：
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
```

- [ ] **Step 3: 创建 commands/whoami.md**

```markdown
---
name: "Whoami"
description: 查看当前 ldc 登录用户信息
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
```

- [ ] **Step 4: Commit**

```bash
git add commands/init.md commands/login.md commands/whoami.md
git commit -m "feat: 添加 init、login、whoami 命令"
```

---

### Task 3: 创建核心部署命令（ship / build）

**Files:**
- Create: `commands/ship.md`
- Create: `commands/build.md`

**Interfaces:**
- Consumes: `ldc` skill 中的前置检查、配置读取、环境选择、安全约束流程
- Produces: 执行 ldc ship/build 命令完成构建和发布

- [ ] **Step 1: 创建 commands/ship.md**

```markdown
---
name: "Ship"
description: 一键构建并发布项目到未来云（测试/生产环境）
category: Deploy
tags: [deploy, build, ship, ldc]
---

一键构建并发布项目到未来云平台。

**输入**: `$ARGUMENTS` 可以是环境标识 `test` 或 `prod`。如果为空则交互式选择。

**步骤**

1. **前置检查**

   按照 `ldc` skill 中的前置检查流程：
   - 检查 `ldc` 是否安装（`which ldc`），未安装则询问是否自动安装
   - 检查登录状态（`ldc whoami`）
   - 未通过则按 skill 中的提示处理并中止

2. **读取项目配置**

   按照 `ldc` skill 中的配置读取流程：
   - 读取当前项目 `.claude/deploy.json`
   - 不存在则提示 "运行 `/init` 初始化配置" 并中止

3. **确定目标环境**

   按照 `ldc` skill 中的环境处理逻辑：
   - `$ARGUMENTS` 为 `test` → 测试环境
   - `$ARGUMENTS` 为 `prod` → 生产环境
   - `$ARGUMENTS` 为空 → 使用 AskUserQuestion 让用户选择

4. **生产环境确认**

   如果目标环境为 `prod`，**必须**使用 AskUserQuestion 进行二次确认：
   - 展示项目名称和目标环境
   - 用户确认后才继续执行

5. **执行 ship**

   根据环境执行对应命令：

   **测试环境：**
   ```bash
   ldc ship <test-appId> -b test
   ```
   设置 `timeout: 600000`（10 分钟）

   **生产环境：**
   ```bash
   ldc ship <prod-appId>
   ```
   设置 `timeout: 600000`（10 分钟）

   > **分支处理：** 测试环境默认使用 `-b test`；生产环境不指定分支，透传给 ldc 的交互式 UI 让用户选择。

   其中 `<test-appId>` 和 `<prod-appId>` 从 `.claude/deploy.json` 的 `apps.test.appId` 和 `apps.prod.appId` 读取。

6. **展示结果**

   - 成功：展示构建摘要（项目、环境、分支、commit），并输出未来云管理页链接（从配置中的 `cloudUrl` 读取）
   - 失败：提示构建失败，输出 cloudUrl 供用户前往未来云查看构建详情
   - 如需审批（qa_audit=1）：提示等待审批，并告知后续执行 `/deploy publish`

**护栏**
- 生产环境发布前**必须**二次确认
- 不执行 `ldc review` 审批操作
- 不执行 `ldc logout`
```

- [ ] **Step 2: 创建 commands/build.md**

```markdown
---
name: "Build"
description: 仅构建项目（打包），不提交发布申请
category: Deploy
tags: [deploy, build, ldc]
---

仅构建项目，不提交发布申请。适合提前验证构建是否通过。

**输入**: `$ARGUMENTS` 可以是环境标识 `test` 或 `prod`。如果为空则交互式选择。

**步骤**

1. **前置检查**

   按照 `ldc` skill 中的前置检查流程：
   - 检查 `ldc` 是否安装（`which ldc`），未安装则询问是否自动安装
   - 检查登录状态（`ldc whoami`）
   - 未通过则按 skill 中的提示处理并中止

2. **读取项目配置**

   按照 `ldc` skill 中的配置读取流程：
   - 读取当前项目 `.claude/deploy.json`
   - 不存在则提示 "运行 `/init` 初始化配置" 并中止

3. **确定目标环境**

   按照 `ldc` skill 中的环境处理逻辑：
   - `$ARGUMENTS` 为 `test` → 测试环境
   - `$ARGUMENTS` 为 `prod` → 生产环境
   - `$ARGUMENTS` 为空 → 使用 AskUserQuestion 让用户选择

4. **执行构建**

   ```bash
   ldc build <appId>
   ```

   其中 `<appId>` 根据目标环境从 `.claude/deploy.json` 中读取对应的 `apps.test.appId` 或 `apps.prod.appId`。

   设置 `timeout: 600000`（10 分钟）

   `ldc build` 会交互式选择分支和 commit，透传给 ldc 的终端 UI。

5. **展示结果**

   - 成功：展示构建摘要，提示"构建完成，未提交发布申请"，输出 cloudUrl
   - 失败：提示构建失败，输出 cloudUrl 供用户前往未来云查看构建详情

**护栏**
- 仅执行构建，不提交发布申请
- 不执行 `ldc review` 审批操作
- 不执行 `ldc logout`
```

- [ ] **Step 3: Commit**

```bash
git add commands/ship.md commands/build.md
git commit -m "feat: 添加 ship 和 build 命令"
```

---

### Task 4: 创建发布管理命令（deploy / rollback / status）

**Files:**
- Create: `commands/deploy.md`
- Create: `commands/rollback.md`
- Create: `commands/status.md`

**Interfaces:**
- Consumes: `ldc` skill 中的前置检查、配置读取、环境选择、安全约束流程
- Produces: 执行 ldc deploy 系列命令完成发布管理

- [ ] **Step 1: 创建 commands/deploy.md**

```markdown
---
name: "Deploy"
description: 发布管理 — 查看待发布列表或执行发布
category: Deploy
tags: [deploy, publish, ldc]
---

发布管理：查看待发布列表或执行已审批的发布。

**输入**: `$ARGUMENTS` 格式为 `[action] [env]`
- `action`: `list`（查看列表）或 `publish`（执行发布），默认 `list`
- `env`: `test` 或 `prod`，如果为空则交互式选择

示例：
- `/deploy list test` → 查看测试环境待发布列表
- `/deploy publish prod` → 发布生产环境
- `/deploy list` → 交互式选择环境，查看列表
- `/deploy publish` → 交互式选择环境，执行发布
- `/deploy` → 默认 list，交互式选择环境

**步骤**

1. **前置检查**

   按照 `ldc` skill 中的前置检查流程：
   - 检查 `ldc` 是否安装（`which ldc`），未安装则询问是否自动安装
   - 检查登录状态（`ldc whoami`）
   - 未通过则按 skill 中的提示处理并中止

2. **读取项目配置**

   按照 `ldc` skill 中的配置读取流程：
   - 读取当前项目 `.claude/deploy.json`
   - 不存在则提示 "运行 `/init` 初始化配置" 并中止

3. **解析参数**

   从 `$ARGUMENTS` 中解析 action 和 env：
   - 第一个词是 action（`list` 或 `publish`）
   - 第二个词是 env（`test` 或 `prod`）
   - 如果只有 action 没有 env → 使用 AskUserQuestion 选择环境
   - 如果都为空 → action 默认 `list`，env 交互式选择

4. **生产环境发布确认**

   如果 action 为 `publish` 且环境为 `prod`，**必须**使用 AskUserQuestion 进行二次确认。

5. **执行命令**

   根据 action 执行对应命令：

   **list（查看待发布列表）：**
   ```bash
   ldc deploy list <appId>
   ```

   **publish（执行发布）：**
   ```bash
   ldc deploy publish <appId>
   ```

   其中 `<appId>` 根据目标环境从 `.claude/deploy.json` 中读取。

   设置 `timeout: 120000`（2 分钟）

6. **展示结果**

   - list 成功：展示待发布记录列表
   - publish 成功：展示发布结果，输出 cloudUrl
   - 失败：展示错误信息和排查建议

**护栏**
- 生产环境发布前**必须**二次确认
- 不执行 `ldc review` 审批操作
- 不执行 `ldc logout`
```

- [ ] **Step 2: 创建 commands/rollback.md**

```markdown
---
name: "Rollback"
description: 回滚到已发布版本的上一版本
category: Deploy
tags: [deploy, rollback, ldc]
---

回滚到已发布版本的上一版本。**这是破坏性操作，无论测试/生产环境都需要二次确认。**

**输入**: `$ARGUMENTS` 可以是环境标识 `test` 或 `prod`。如果为空则交互式选择。

**步骤**

1. **前置检查**

   按照 `ldc` skill 中的前置检查流程：
   - 检查 `ldc` 是否安装（`which ldc`），未安装则询问是否自动安装
   - 检查登录状态（`ldc whoami`）
   - 未通过则按 skill 中的提示处理并中止

2. **读取项目配置**

   按照 `ldc` skill 中的配置读取流程：
   - 读取当前项目 `.claude/deploy.json`
   - 不存在则提示 "运行 `/init` 初始化配置" 并中止

3. **确定目标环境**

   按照 `ldc` skill 中的环境处理逻辑：
   - `$ARGUMENTS` 为 `test` → 测试环境
   - `$ARGUMENTS` 为 `prod` → 生产环境
   - `$ARGUMENTS` 为空 → 使用 AskUserQuestion 让用户选择

4. **二次确认**

   **必须**使用 AskUserQuestion 进行二次确认（无论测试/生产环境）：
   - 展示项目名称、目标环境
   - 明确提示"回滚是破坏性操作，将恢复到上一发布版本"
   - 用户确认后才继续执行

5. **执行回滚**

   ```bash
   ldc deploy rollback <appId>
   ```

   其中 `<appId>` 根据目标环境从 `.claude/deploy.json` 中读取。

   设置 `timeout: 120000`（2 分钟）

6. **展示结果**

   - 成功：展示回滚结果，输出 cloudUrl
   - 失败：展示错误信息和排查建议

**护栏**
- **任何环境**回滚前都必须二次确认
- 不执行 `ldc review` 审批操作
- 不执行 `ldc logout`
```

- [ ] **Step 3: 创建 commands/status.md**

```markdown
---
name: "Status"
description: 查看项目部署状态和最近发布记录
category: Deploy
tags: [deploy, status, ldc]
---

查看项目的部署状态和最近发布记录。

**输入**: `$ARGUMENTS` 可以是环境标识 `test` 或 `prod`。如果为空则交互式选择。

**步骤**

1. **前置检查**

   按照 `ldc` skill 中的前置检查流程：
   - 检查 `ldc` 是否安装（`which ldc`），未安装则询问是否自动安装
   - 检查登录状态（`ldc whoami`）
   - 未通过则按 skill 中的提示处理并中止

2. **读取项目配置**

   按照 `ldc` skill 中的配置读取流程：
   - 读取当前项目 `.claude/deploy.json`
   - 不存在则提示 "运行 `/init` 初始化配置" 并中止

3. **确定目标环境**

   按照 `ldc` skill 中的环境处理逻辑：
   - `$ARGUMENTS` 为 `test` → 测试环境
   - `$ARGUMENTS` 为 `prod` → 生产环境
   - `$ARGUMENTS` 为空 → 使用 AskUserQuestion 让用户选择

4. **查询状态**

   ```bash
   ldc deploy list <appId>
   ```

   其中 `<appId>` 根据目标环境从 `.claude/deploy.json` 中读取。

   设置 `timeout: 120000`（2 分钟）

5. **展示结果**

   - 成功：展示最近的发布记录列表（版本、状态、时间、操作人）
   - 输出 cloudUrl 供用户前往未来云查看更多详情
   - 失败：展示错误信息

**护栏**
- 只读操作，不执行任何修改
- 不执行 `ldc logout`
```

- [ ] **Step 4: Commit**

```bash
git add commands/deploy.md commands/rollback.md commands/status.md
git commit -m "feat: 添加 deploy、rollback、status 命令"
```

---

### Task 5: 创建审批命令（review）

**Files:**
- Create: `commands/review.md`

**Interfaces:**
- Consumes: `ldc` skill 中的前置检查流程（仅安装+登录检查，不需要项目配置）
- Produces: 执行 ldc review 完成审批

- [ ] **Step 1: 创建 commands/review.md**

```markdown
---
name: "Review"
description: 批量审批项目发布和团队申请
category: Deploy
tags: [deploy, review, approve, ldc]
---

查看和批量审批项目发布申请和团队申请。

**输入**: 无参数

**步骤**

1. **前置检查**

   按照 `ldc` skill 中的前置检查流程：
   - 检查 `ldc` 是否安装（`which ldc`），未安装则询问是否自动安装
   - 检查登录状态（`ldc whoami`）
   - 未通过则按 skill 中的提示处理并中止

   > 注意：`/review` 不需要项目配置（`.claude/deploy.json`），因为审批操作与具体项目无关。

2. **执行审批**

   ```bash
   ldc review
   ```
   设置 `timeout: 60000`（1 分钟）

   `ldc review` 是交互式命令，流程：
   1. 选择审批类型（项目发布 / 团队申请），显示待审批数量
   2. 选择操作（通过 / 拒绝）
   3. 多选待审批项（空格多选，a 全选）
   4. 确认后批量执行，实时展示进度

   Claude Code 会在终端中直接运行此命令，用户可以进行交互操作。

3. **展示结果**

   审批完成后展示操作结果摘要。

**护栏**
- 审批操作通过 ldc 的交互式 UI 进行，由用户自主确认
- 不执行 `ldc logout`
```

- [ ] **Step 2: Commit**

```bash
git add commands/review.md
git commit -m "feat: 添加 review 审批命令"
```

---

### Task 6: 重写 README.md 和清理

**Files:**
- Modify: `README.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: 所有前序 Task 产出的文件
- Produces: 最终可分发的 Plugin 仓库

- [ ] **Step 1: 重写 README.md**

覆盖 `README.md`:

```markdown
# LDC Deploy Plugin

未来云一键部署 Claude Code 插件 — 通过斜杠命令完成项目构建、发布、审批、回滚。

## 安装

```bash
claude plugin add github:bfe-ledu/deploy
```

## 前置要求

- Node.js >= 18
- macOS（扫码登录依赖系统浏览器 profile）
- `ledu-cloud-cli` 已安装（未安装时插件会询问是否自动安装）

## 快速开始

```bash
# 1. 登录
/login

# 2. 初始化项目配置
/init

# 3. 一键部署测试环境
/ship test
```

## 命令速览

| 命令 | 说明 |
|------|------|
| `/ship [test\|prod]` | 一键构建+发布 |
| `/build [test\|prod]` | 仅构建，不发布 |
| `/deploy [list\|publish] [test\|prod]` | 发布管理 |
| `/rollback [test\|prod]` | 回滚到上一版本 |
| `/review` | 批量审批发布/团队申请 |
| `/whoami` | 查看当前登录用户 |
| `/status [test\|prod]` | 查看项目部署状态 |
| `/login` | 扫码登录 |
| `/init` | 初始化项目部署配置 |

## 项目配置

每个项目在 `.claude/deploy.json` 中配置部署信息：

```json
{
  "projectName": "我的项目",
  "apps": {
    "test": {
      "appId": "12345",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=12345"
    },
    "prod": {
      "appId": "67890",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=67890"
    }
  }
}
```

运行 `/init` 可以交互式生成此文件。

## 推荐工作流

### 测试环境日常部署

```bash
/ship test
```

指定 test 分支，自动取最新 commit，一键完成构建+发布。

### 生产环境部署

```bash
/ship prod
```

会进行二次确认，然后通过 ldc 交互式 UI 选择分支。

### 需要审批的项目

```bash
# 1. 提交构建和申请
/ship prod

# 2. 等待审批通过后，执行发布
/deploy publish prod
```

### 回滚

```bash
/rollback prod
```

选择历史版本，回滚到指定版本（需二次确认）。

### 批量审批

```bash
/review
```

交互式审批项目发布和团队申请。

## 安全设计

- **生产环境操作必须二次确认** — `/ship prod`、`/deploy publish prod`
- **回滚操作必须二次确认** — 无论测试/生产环境
- **不自动执行 `ldc logout`** — 避免意外清除凭证
- **配置缺失时中止** — 不猜测 appId，引导用户 `/init`

## License

MIT
```

- [ ] **Step 2: 更新 .gitignore**

在 `.gitignore` 末尾追加：

```
# Claude Code
.claude/
!.claude-plugin/

# Node
node_modules/
```

- [ ] **Step 3: Commit**

```bash
git add README.md .gitignore
git commit -m "docs: 重写 README 并更新 .gitignore"
```

---

### Task 7: 验证 Plugin 结构完整性

**Files:**
- 验证所有文件存在且格式正确

- [ ] **Step 1: 验证文件结构**

运行:
```bash
find . -not -path './.git/*' -type f | sort
```

预期输出包含：
```
./.claude-plugin/plugin.json
./.gitignore
./LICENSE
./README.md
./commands/build.md
./commands/deploy.md
./commands/init.md
./commands/login.md
./commands/review.md
./commands/rollback.md
./commands/ship.md
./commands/status.md
./commands/whoami.md
./docs/superpowers/plans/2026-06-23-ldc-plugin.md
./docs/superpowers/specs/2026-06-23-ldc-plugin-design.md
./skills/ldc/SKILL.md
```

- [ ] **Step 2: 验证 plugin.json 格式**

```bash
cat .claude-plugin/plugin.json | python3 -m json.tool
```

预期：JSON 解析成功，无报错

- [ ] **Step 3: 验证 command 文件 frontmatter**

```bash
for f in commands/*.md; do echo "=== $f ==="; head -6 "$f"; echo; done
```

预期：每个文件开头都有 `---` 包围的 YAML frontmatter，包含 `name`、`description`、`category`、`tags`

- [ ] **Step 4: 本地安装测试**

```bash
claude plugin add /Users/zhaoxin/code/ledu/bfe-tech/deploy
```

预期：Plugin 安装成功，9 个命令可用

- [ ] **Step 5: 最终 Commit（如有修复）**

如果验证中发现问题并修复：
```bash
git add -A
git commit -m "fix: 修复 plugin 结构问题"
```
