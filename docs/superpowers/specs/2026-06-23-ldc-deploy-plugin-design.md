# LDC Deploy Plugin — 设计文档

**日期：** 2026-06-23  
**作者：** zhaoxin  
**状态：** 草案

---

## 1. 概述

### 目标

从头设计一个 Claude Code Plugin，让团队前端开发人员通过 `/ship test` 等斜杠命令，一键完成项目在未来云平台的构建、发布、审批和回滚操作。

### 核心决策

| 维度 | 选择 | 理由 |
|------|------|------|
| 架构 | 纯 Skill + Commands（方案 A） | 零代码、零依赖，纯 Markdown 维护成本最低 |
| 目标用户 | 团队分发 | 通过 GitHub 仓库安装，开箱即用 |
| 配置方式 | 兼容两种 | 优先读项目配置，无配置时引导 /init |
| CLI 依赖 | ledu-cloud-cli (ldc) | 复用已有 CLI 能力，Plugin 只做编排 |

---

## 2. 目录结构

```
bfe-tech/deploy/
├── .claude-plugin/
│   └── plugin.json              # 插件元信息
├── skills/
│   └── ldc-deploy/
│       └── SKILL.md             # 核心技能：前置检查、配置读取、环境逻辑
├── commands/
│   ├── ship.md                  # /ship [test|prod]
│   ├── build.md                 # /build [test|prod]
│   ├── deploy.md                # /deploy [list|publish] [test|prod]
│   ├── rollback.md              # /rollback [test|prod]
│   ├── review.md                # /review
│   ├── whoami.md                # /whoami
│   ├── status.md                # /status [test|prod]
│   ├── login.md                 # /login
│   └── init.md                  # /init
├── README.md
├── LICENSE
└── .gitignore
```

---

## 3. 命令总览

| 命令 | 输入 | 说明 | 需要项目配置 |
|------|------|------|:---:|
| `/ship [test\|prod]` | 环境标识 | 一键构建+发布 | ✓ |
| `/build [test\|prod]` | 环境标识 | 仅构建，不发布 | ✓ |
| `/deploy [list\|publish] [test\|prod]` | action + 环境 | 发布管理 | ✓ |
| `/rollback [test\|prod]` | 环境标识 | 回滚到上一版本 | ✓ |
| `/review` | 无 | 批量审批发布/团队申请 | ✗ |
| `/whoami` | 无 | 查看当前登录用户 | ✗ |
| `/status [test\|prod]` | 环境标识 | 查看项目部署状态 | ✓ |
| `/login` | 无 | 扫码登录 | ✗ |
| `/init` | 无 | 初始化项目 deploy.json | ✗ |

---

## 4. Skill 核心逻辑 (`ldc-deploy`)

### 4.1 共享模块

| 模块 | 职责 |
|------|------|
| 前置检查 | 检查 ldc 安装 → 检查登录状态 |
| 配置读取 | 读取 `.claude/deploy.json`，缺失时引导 /init |
| 环境选择 | 参数指定 or AskUserQuestion 交互选择 |
| 安全约束 | 生产环境二次确认、回滚必须确认、禁止 logout |
| 结果展示 | 成功/失败/需审批 三种输出模板 |

### 4.2 前置检查

```
Step 1: which ldc
  ├── 有输出 → 继续
  └── 无输出 → AskUserQuestion 询问是否自动安装
                ├── 用户同意 → 执行: npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/
                │              安装完成后继续
                └── 用户拒绝 → 中止执行

Step 2: ldc whoami
  ├── 返回用户信息 → 继续
  └── 报错/未登录 → 提示: 执行 /login 或 ldc login
                          中止执行
```

### 4.3 配置读取

**配置文件路径：** `<项目根目录>/.claude/deploy.json`

**配置格式：**

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

**读取流程：**

1. 查找当前项目根目录的 `.claude/deploy.json`
2. 解析 JSON 获取 `apps` 对象
3. 根据目标环境（test/prod）获取对应的 `appId` 和 `cloudUrl`
4. 不存在时提示 "运行 /init 初始化配置" 并中止

### 4.4 环境选择逻辑

1. 如果命令参数指定了环境（`test` 或 `prod`）→ 直接使用
2. 如果未指定 → 使用 AskUserQuestion 让用户选择

### 4.5 安全约束

| 场景 | 约束 |
|------|------|
| `/ship prod` | 必须 AskUserQuestion 二次确认 |
| `/deploy publish prod` | 必须 AskUserQuestion 二次确认 |
| `/rollback` (任何环境) | 必须 AskUserQuestion 二次确认（破坏性操作） |
| `ldc logout` | 不自动执行 |
| `/review` | 展示详细列表，由用户确认 |

### 4.6 超时策略

| 命令类型 | 超时时间 | 原因 |
|----------|----------|------|
| ship, build | 600000ms (10min) | 构建过程耗时较长 |
| deploy, rollback, status | 120000ms (2min) | API 操作，正常较快 |
| review, whoami, login | 60000ms (1min) | 简单操作 |

---

## 5. 各命令详细设计

### 5.1 `/init` — 初始化项目配置

**输入：** 无参数

**流程：**

1. 检查 `.claude/deploy.json` 是否已存在
   - 已存在 → 展示当前配置，询问是否覆盖
   - 不存在 → 继续
2. 通过 AskUserQuestion 收集信息：
   - 项目名称
   - 测试环境 App ID
   - 生产环境 App ID（可选）
3. 生成 `.claude/deploy.json` 并写入
4. 展示配置摘要，提示 "配置已生成，现在可以使用 /ship test 部署"

---

### 5.2 `/login` — 登录

**输入：** 无参数

**流程：**

1. 执行 `ldc whoami` 检查登录状态
   - 已登录 → 展示用户信息，提示"已登录，无需重复操作"，结束
2. 未登录 → 直接执行 `ldc login` (timeout: 60000)
3. 完成后执行 `ldc whoami` 验证登录成功
4. 展示登录结果

---

### 5.3 `/whoami` — 查看用户信息

**输入：** 无参数

**流程：**

1. 执行 `ldc whoami` (timeout: 60000)
2. 展示用户信息

---

### 5.4 `/ship [test|prod]` — 一键构建+发布

**输入：** `$ARGUMENTS` = `test` 或 `prod` 或空

**流程：**

1. 前置检查（引用 Skill 4.2）
2. 读取配置（引用 Skill 4.3）
3. 确定环境（引用 Skill 4.4）
4. 如果环境为 `prod` → AskUserQuestion 二次确认
5. 执行命令：
   - 测试环境：`ldc ship <apps.test.appId> -b test` (timeout: 600000)
   - 生产环境：`ldc ship <apps.prod.appId>` (timeout: 600000)
   
   > **分支处理：** 测试环境默认使用 `-b test`；生产环境不指定分支，透传给 ldc 的交互式 UI 让用户选择。

6. 展示结果：
   - 成功 → 构建摘要 + cloudUrl 链接
   - 失败 → 错误信息 + cloudUrl 链接（查看详情）
   - 需审批 → 提示等待审批，后续执行 `/deploy publish`

---

### 5.5 `/build [test|prod]` — 仅构建

**输入：** `$ARGUMENTS` = `test` 或 `prod` 或空

**流程：**

1. 前置检查
2. 读取配置
3. 确定环境
4. 执行：`ldc build <appId>` (timeout: 600000)
5. 展示结果：
   - 成功 → "构建完成，未提交发布申请" + cloudUrl
   - 失败 → 错误信息 + cloudUrl

---

### 5.6 `/deploy [action] [env]` — 发布管理

**输入：** `$ARGUMENTS` = `[list|publish] [test|prod]`

**参数解析：**
- 第一个词 = action（`list` 或 `publish`），默认 `list`
- 第二个词 = env（`test` 或 `prod`），缺失时交互选择

**流程：**

1. 前置检查
2. 读取配置
3. 解析参数得到 action 和 env
4. 如果 action=`publish` 且 env=`prod` → 二次确认
5. 执行：
   - list：`ldc deploy list <appId>` (timeout: 120000)
   - publish：`ldc deploy publish <appId>` (timeout: 120000)
6. 展示结果

---

### 5.7 `/rollback [test|prod]` — 回滚

**输入：** `$ARGUMENTS` = `test` 或 `prod` 或空

**流程：**

1. 前置检查
2. 读取配置
3. 确定环境
4. **必须**二次确认（无论测试/生产）— 回滚是破坏性操作
5. 执行：`ldc deploy rollback <appId>` (timeout: 120000)
6. 展示回滚结果

---

### 5.8 `/review` — 批量审批

**输入：** 无参数

**流程：**

1. 前置检查（仅检查 ldc 安装和登录状态，不需要项目配置）
2. 执行：`ldc review` (timeout: 60000)
3. 展示审批结果

**注意：** `ldc review` 是交互式命令（空格多选、a 全选），Claude Code 会在终端中直接运行，用户可以交互操作。

---

### 5.9 `/status [test|prod]` — 查看部署状态

**输入：** `$ARGUMENTS` = `test` 或 `prod` 或空

**流程：**

1. 前置检查
2. 读取配置
3. 确定环境
4. 执行：`ldc deploy list <appId>` (timeout: 120000)
5. 展示最近的发布记录

---

## 6. 安装与分发

### 安装方式

```bash
# 通过 GitHub 仓库安装
claude plugin add github:bfe-ledu/deploy

# 本地安装（开发/测试用）
claude plugin add /path/to/bfe-tech/deploy
```

### 团队上手流程

```bash
# 1. 安装插件
claude plugin add github:bfe-ledu/deploy

# 2. 登录
/login

# 3. 在项目中初始化配置
/init

# 4. 一键部署测试环境
/ship test
```

### 前置要求

- Node.js >= 18
- macOS（扫码登录依赖系统浏览器 profile）
- `@ld/cloud-cli` 已安装（未安装时 Plugin 会询问是否自动安装）：`npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/`

---

## 7. plugin.json

```json
{
  "name": "ldc-deploy",
  "description": "未来云一键部署 — 通过 ldc CLI 完成构建、发布、审批、回滚",
  "version": "1.0.0",
  "author": { "name": "bfe-ledu", "email": "p_zhaoxin10@ledupeiyou.com" },
  "homepage": "https://github.com/bfe-ledu/deploy",
  "repository": "https://github.com/bfe-ledu/deploy",
  "license": "MIT",
  "keywords": ["cloud", "deploy", "ldc", "ship", "build", "review", "rollback"]
}
```

---

## 8. 护栏与约束

1. **生产环境操作必须二次确认** — ship prod / deploy publish prod / rollback（任何环境）
2. **不自动执行 ldc logout** — 避免意外清除凭证
3. **不修改项目代码** — Plugin 只执行部署操作，不改动源码
4. **配置缺失时中止** — 不猜测 appId，引导用户 /init
5. **命令独立** — 每个命令可以单独使用，不强制执行顺序
