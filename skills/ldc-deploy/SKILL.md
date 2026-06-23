---
name: ldc-deploy
description: 通过 ledu-cloud-cli (ldc) 进行项目构建和部署。支持测试环境和生产环境的一键 ship、build、deploy、rollback、review 操作。
disable-model-invocation: true
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
