# LDC Deploy Plugin

未来云一键部署 Claude Code 插件 — 通过斜杠命令完成项目构建、发布、审批。

## 调试

- 本目录

```bash
claude --plugin-dir .
```

- 其他目录

```bash
claude --plugin-dir <绝对路径>
```

## 安装

- 注册 marketplace

  ```bash
  claude plugin add bfe-ledu/ledu-marketplace
  ```

- 从注册的marketplace add 本插件

  ```bash
  claude plugin add ldc/ledu-marketplace
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
| `/review` | 批量审批发布/团队申请 |
| `/whoami` | 查看当前登录用户 |
| `/status [test\|prod]` | 查看项目部署状态 |
| `/login` | 扫码登录 |
| `/init` | 初始化项目部署配置 |

## 项目配置

每个项目在 `.ldc.json` 中配置部署信息：

```json
{
  "test": "12345",
  "prod": "67890"
}
```

运行 `/init` 可以交互式生成此文件。

## 推荐工作流

### 测试环境日常部署

```bash
/ship test
```

自动取最近分支供选择，一键完成构建+发布。

### 生产环境部署

```bash
/ship prod
```

会进行二次确认，然后选择分支部署。

### 仅构建（验证打包）

```bash
/build test
```

交互式选择分支和 commit，只打包不发布。适合提前验证构建是否通过。

### 需要审批的项目

```bash
# 1. 提交构建和申请
/ship prod

# 2. 等待审批通过后，执行发布
/deploy publish prod
```

### 批量审批

```bash
/review
```

交互式审批项目发布和团队申请。

## 安全设计

- **生产环境操作必须二次确认** — `/ship prod`、`/deploy publish prod`
- **不自动执行 `ldc logout`** — 避免意外清除凭证
- **配置缺失时中止** — 不猜测 appId，引导用户 `/init`

## License

MIT
