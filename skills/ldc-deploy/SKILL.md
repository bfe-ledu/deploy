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

### 登录二维码模式

用于 login 命令，后台执行并用 Read 展示完整二维码：

1. `Bash(run_in_background): ldc login 2>&1 | tee /tmp/ldc-login-output.txt`
2. 等待 3 秒让二维码生成
3. `Read: /tmp/ldc-login-output.txt` — 展示完整 ASCII 二维码
4. 等待后台任务完成（用户扫码后自动退出）
5. `Bash: ldc whoami` 验证登录成功

### 透传执行模式

用于 review 等自带交互式 UI 的 ldc 命令：

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
