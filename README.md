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
/ldc:login

# 2. 初始化项目配置
/ldc:init

# 3. 一键部署测试环境
/ldc:ship test
```

## 命令速览

| 命令 | 说明 |
|------|------|
| `/ldc:ship [test\|prod]` | 一键构建+发布 |
| `/ldc:build [test\|prod]` | 仅构建，不发布 |
| `/ldc:deploy [list\|publish] [test\|prod]` | 发布管理 |
| `/ldc:rollback [test\|prod]` | 回滚到上一版本 |
| `/ldc:review` | 批量审批发布/团队申请 |
| `/ldc:whoami` | 查看当前登录用户 |
| `/ldc:status [test\|prod]` | 查看项目部署状态 |
| `/ldc:login` | 扫码登录 |
| `/ldc:init` | 初始化项目部署配置 |

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

运行 `/ldc:init` 可以交互式生成此文件。

## 推荐工作流

### 测试环境日常部署

```bash
/ldc:ship test
```

指定 test 分支，自动取最新 commit，一键完成构建+发布。

### 生产环境部署

```bash
/ldc:ship prod
```

会进行二次确认，然后通过 ldc 交互式 UI 选择分支。

### 需要审批的项目

```bash
# 1. 提交构建和申请
/ldc:ship prod

# 2. 等待审批通过后，执行发布
/ldc:deploy publish prod
```

### 回滚

```bash
/ldc:rollback prod
```

选择历史版本，回滚到指定版本（需二次确认）。

### 批量审批

```bash
/ldc:review
```

交互式审批项目发布和团队申请。

## 安全设计

- **生产环境操作必须二次确认** — `/ldc:ship prod`、`/ldc:deploy publish prod`
- **回滚操作必须二次确认** — 无论测试/生产环境
- **不自动执行 `ldc logout`** — 避免意外清除凭证
- **配置缺失时中止** — 不猜测 appId，引导用户 `/ldc:init`

## License

MIT
