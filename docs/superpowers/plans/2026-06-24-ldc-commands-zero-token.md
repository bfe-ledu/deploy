# LDC Commands Zero-Token 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将所有 `/ldc:*` 斜杠命令迁移为 Hook + Shell 脚本直接执行，实现零 token 消耗、零 context 占用。

**Architecture:** UserPromptSubmit hook 拦截所有 `/ldc:*` 命令，路由到对应的 shell 脚本执行，返回 `{"decision": "block"}` 阻止模型处理。脚本通过 `_common.sh` 共享前置检查、配置读取、环境选择等逻辑。

**Tech Stack:** Bash (shell scripts), jq (JSON parsing), Claude Code hooks (UserPromptSubmit)

## Global Constraints

- Shell 脚本兼容 bash 4.0+（macOS 默认 zsh 下通过 `/bin/bash` 调用）
- 依赖 `jq` 用于 JSON 解析（macOS 通过 Homebrew 可用）
- 所有脚本使用 `set -euo pipefail` 严格模式
- 交互确认使用 `read -p`，环境选择使用 `select`
- 生产环境操作和回滚操作必须要求输入 `yes` 确认
- 文件路径相对于插件安装目录（非用户项目目录）

---

## File Map

| 文件 | 职责 |
|------|------|
| `scripts/_common.sh` | 共享函数：颜色输出、前置检查、配置读取、环境选择、安全确认 |
| `scripts/whoami.sh` | 查看登录用户 |
| `scripts/login.sh` | 扫码登录 |
| `scripts/init.sh` | 初始化 deploy.json 配置 |
| `scripts/ship.sh` | 一键构建+发布 |
| `scripts/build.sh` | 仅构建不发布 |
| `scripts/deploy.sh` | 发布管理（list/publish） |
| `scripts/rollback.sh` | 回滚 |
| `scripts/status.sh` | 查看部署状态 |
| `scripts/review.sh` | 批量审批 |
| `hooks/intercept.sh` | Hook 入口：检测 LDC 命令，路由到脚本 |
| `.claude/settings.local.json` | Hook 配置 |
| `commands/*.md` | 缩减为仅 frontmatter + 标记（9 个文件） |
| `skills/ldc-deploy/SKILL.md` | 删除 |

---

### Task 1: 创建共享函数库 `scripts/_common.sh`

**Files:**
- Create: `scripts/_common.sh`

**Interfaces:**
- Consumes: 用户项目中的 `.claude/deploy.json`
- Produces: 以下函数供所有命令脚本 `source` 使用：
  - `info(msg)`, `warn(msg)`, `error(msg)`, `heading(msg)` — 带颜色输出
  - `check_ldc_installed()` — 检查/安装 ldc
  - `check_logged_in()` — 检查登录状态
  - `preflight()` — 完整前置检查
  - `load_config()` — 读取 deploy.json
  - `get_app_id(env)` — 获取 appId
  - `get_cloud_url(env)` — 获取管理页 URL
  - `get_project_name()` — 获取项目名
  - `resolve_env(arg)` — 环境参数解析/交互选择
  - `confirm_prod()` — 生产环境确认
  - `confirm_danger(action, env)` — 危险操作确认

- [ ] **Step 1: 创建 scripts 目录和 _common.sh**

```bash
mkdir -p scripts
```

写入 `scripts/_common.sh`:

```bash
#!/bin/bash
set -euo pipefail

# ─── 颜色 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1" >&2; exit 1; }
heading() { echo -e "\n${CYAN}▸ $1${NC}"; }

# ─── 前置检查 ───

check_ldc_installed() {
  if ! command -v ldc &>/dev/null; then
    read -p "$(echo -e "${YELLOW}ldc 未安装，是否自动安装？[y/N]${NC} ")" yn
    [[ "$yn" =~ ^[Yy]$ ]] || error "请手动安装: npm i -g ledu-cloud-cli"
    npm install -g ledu-cloud-cli --registry=https://registry.npmjs.org/
    info "ldc 安装完成"
  fi
}

check_logged_in() {
  if ! ldc whoami &>/dev/null; then
    error "未登录，请先执行: ldc login"
  fi
}

preflight() {
  check_ldc_installed
  check_logged_in
}

# ─── 配置读取 ───

DEPLOY_CONFIG=".claude/deploy.json"

load_config() {
  [[ -f "$DEPLOY_CONFIG" ]] || error "配置不存在，请先运行 /ldc:init"
  cat "$DEPLOY_CONFIG"
}

get_app_id() {
  local env="$1"
  local app_id
  app_id=$(load_config | jq -r ".apps.${env}.appId // empty")
  [[ -n "$app_id" ]] || error "未找到 ${env} 环境的 appId，请检查 $DEPLOY_CONFIG"
  echo "$app_id"
}

get_cloud_url() {
  local env="$1"
  load_config | jq -r ".apps.${env}.cloudUrl // empty"
}

get_project_name() {
  load_config | jq -r '.projectName // "未知项目"'
}

# ─── 环境处理 ───

resolve_env() {
  local arg="${1:-}"
  if [[ "$arg" == "test" || "$arg" == "prod" ]]; then
    echo "$arg"
    return
  fi
  # 交互式选择
  echo "选择目标环境：" >&2
  select env in "test" "prod"; do
    if [[ -n "$env" ]]; then
      echo "$env"
      return
    fi
  done
}

# ─── 安全确认 ───

confirm_prod() {
  local project
  project=$(get_project_name)
  echo ""
  warn "即将操作 ${RED}生产环境${NC}"
  echo "  项目: $project"
  echo ""
  read -p "确认继续？输入 yes 执行: " yn
  [[ "$yn" == "yes" ]] || error "已取消"
}

confirm_danger() {
  local action="$1"
  local env="$2"
  local project
  project=$(get_project_name)
  echo ""
  warn "即将执行 ${RED}${action}${NC} — ${env} 环境"
  echo "  项目: $project"
  echo ""
  read -p "确认继续？输入 yes 执行: " yn
  [[ "$yn" == "yes" ]] || error "已取消"
}
```

- [ ] **Step 2: 设置可执行权限**

```bash
chmod +x scripts/_common.sh
```

- [ ] **Step 3: 验证语法**

Run: `bash -n scripts/_common.sh`
Expected: 无输出（语法正确）

- [ ] **Step 4: Commit**

```bash
git add scripts/_common.sh
git commit -m "feat: 添加 shell 脚本共享函数库"
```

---

### Task 2: 创建 9 个命令脚本

**Files:**
- Create: `scripts/whoami.sh`
- Create: `scripts/login.sh`
- Create: `scripts/init.sh`
- Create: `scripts/ship.sh`
- Create: `scripts/build.sh`
- Create: `scripts/deploy.sh`
- Create: `scripts/rollback.sh`
- Create: `scripts/status.sh`
- Create: `scripts/review.sh`

**Interfaces:**
- Consumes: `scripts/_common.sh` 中的所有共享函数
- Produces: 可独立执行的命令脚本，接受一个字符串参数 `$1`（对应原 `$ARGUMENTS`）

- [ ] **Step 1: 创建 scripts/whoami.sh**

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Whoami"
check_ldc_installed

if ldc whoami &>/dev/null; then
  info "当前用户:"
  ldc whoami
else
  warn "未登录，请执行: ldc login"
fi
```

- [ ] **Step 2: 创建 scripts/login.sh**

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Login"
check_ldc_installed

if ldc whoami &>/dev/null; then
  info "已登录: $(ldc whoami)"
  read -p "是否重新登录？[y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 0
fi

ldc login

if ldc whoami &>/dev/null; then
  info "登录成功: $(ldc whoami)"
else
  error "登录失败"
fi
```

- [ ] **Step 3: 创建 scripts/init.sh**

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Init"

CONFIG_DIR=".claude"
CONFIG_FILE="$CONFIG_DIR/deploy.json"

if [[ -f "$CONFIG_FILE" ]]; then
  warn "配置已存在: $CONFIG_FILE"
  cat "$CONFIG_FILE" | jq .
  read -p "是否覆盖？[y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 0
fi

read -p "项目名称: " PROJECT_NAME
[[ -n "$PROJECT_NAME" ]] || error "项目名称不能为空"

read -p "测试环境 App ID: " TEST_APP_ID
read -p "生产环境 App ID: " PROD_APP_ID

[[ -n "$TEST_APP_ID" || -n "$PROD_APP_ID" ]] || error "至少需要一个环境的 App ID"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
{
  "projectName": "$PROJECT_NAME",
  "apps": {
    "test": {
      "appId": "$TEST_APP_ID",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=$TEST_APP_ID"
    },
    "prod": {
      "appId": "$PROD_APP_ID",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=$PROD_APP_ID"
    }
  }
}
EOF

info "配置已生成: $CONFIG_FILE"
cat "$CONFIG_FILE" | jq .
```

- [ ] **Step 4: 创建 scripts/ship.sh**

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Ship"
preflight

ENV=$(resolve_env "${1:-}")
APP_ID=$(get_app_id "$ENV")

if [[ "$ENV" == "prod" ]]; then
  confirm_prod
  info "正在发布到生产环境..."
  ldc ship "$APP_ID"
else
  info "正在发布到测试环境..."
  ldc ship "$APP_ID" -b test
fi

CLOUD_URL=$(get_cloud_url "$ENV")
echo ""
info "ship 完成"
[[ -n "$CLOUD_URL" ]] && echo "  查看详情: $CLOUD_URL"
```

- [ ] **Step 5: 创建 scripts/build.sh**

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Build"
preflight

ENV=$(resolve_env "${1:-}")
APP_ID=$(get_app_id "$ENV")

info "正在构建（${ENV}）..."
ldc build "$APP_ID"

echo ""
info "构建完成"
```

- [ ] **Step 6: 创建 scripts/deploy.sh**

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Deploy"
preflight

# 解析参数：第一个词为 action，第二个词为 env
ARGS="${1:-}"
ACTION=$(echo "$ARGS" | awk '{print $1}')
ENV_ARG=$(echo "$ARGS" | awk '{print $2}')

case "$ACTION" in
  list|ls)
    ENV=$(resolve_env "$ENV_ARG")
    APP_ID=$(get_app_id "$ENV")
    info "查询发布列表（${ENV}）..."
    ldc deploy list "$APP_ID"
    ;;
  publish|p)
    ENV=$(resolve_env "$ENV_ARG")
    APP_ID=$(get_app_id "$ENV")
    if [[ "$ENV" == "prod" ]]; then
      confirm_prod
    fi
    info "执行发布（${ENV}）..."
    ldc deploy publish "$APP_ID"
    info "发布完成"
    ;;
  *)
    echo "用法: /ldc:deploy <action> [env]"
    echo ""
    echo "  list [test|prod]     查看待发布列表"
    echo "  publish [test|prod]  执行发布"
    exit 1
    ;;
esac
```

- [ ] **Step 7: 创建 scripts/rollback.sh**

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Rollback"
preflight

ENV=$(resolve_env "${1:-}")
APP_ID=$(get_app_id "$ENV")

confirm_danger "回滚" "$ENV"

info "正在回滚（${ENV}）..."
ldc deploy rollback "$APP_ID"

CLOUD_URL=$(get_cloud_url "$ENV")
echo ""
info "回滚完成"
[[ -n "$CLOUD_URL" ]] && echo "  查看详情: $CLOUD_URL"
```

- [ ] **Step 8: 创建 scripts/status.sh**

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Status"
preflight

ENV=$(resolve_env "${1:-}")
APP_ID=$(get_app_id "$ENV")

info "查询部署状态（${ENV}）..."
ldc deploy list "$APP_ID"

CLOUD_URL=$(get_cloud_url "$ENV")
[[ -n "$CLOUD_URL" ]] && echo -e "\n  管理页: $CLOUD_URL"
```

- [ ] **Step 9: 创建 scripts/review.sh**

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Review"
preflight

info "进入审批管理..."
ldc review
```

- [ ] **Step 10: 设置所有脚本可执行权限**

```bash
chmod +x scripts/*.sh
```

- [ ] **Step 11: 验证所有脚本语法**

Run: `for f in scripts/*.sh; do bash -n "$f" && echo "OK: $f"; done`
Expected: 每个文件输出 `OK: scripts/<name>.sh`

- [ ] **Step 12: Commit**

```bash
git add scripts/
git commit -m "feat: 添加 9 个 LDC 命令 shell 脚本"
```

---

### Task 3: 创建 Hook 拦截脚本

**Files:**
- Create: `hooks/intercept.sh`

**Interfaces:**
- Consumes: stdin JSON（Claude Code hook input，包含 `.input.prompt` 字段）
- Produces: stdout JSON `{"decision": "block"}` 或 `{"decision": "approve"}`；拦截成功时执行对应 `scripts/<cmd>.sh`

- [ ] **Step 1: 创建 hooks 目录和 intercept.sh**

```bash
mkdir -p hooks
```

写入 `hooks/intercept.sh`:

```bash
#!/bin/bash

# LDC Command Hook Interceptor
# 拦截 /ldc:* 斜杠命令，直接执行对应 shell 脚本，绕过模型推理。
#
# 双重匹配策略：
# 1. 原始命令匹配 — prompt 以 /ldc: 开头（命令未被展开）
# 2. 展开标记匹配 — prompt 包含 <!-- LDC_CMD:xxx -->（命令已展开为 markdown）

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.input.prompt // empty')

CMD=""
ARGS=""

# 策略 1：直接匹配 /ldc: 前缀
if [[ "$PROMPT" =~ ^/ldc:([a-z]+)(\ .*)? ]]; then
  CMD="${BASH_REMATCH[1]}"
  ARGS="${BASH_REMATCH[2]## }"
# 策略 2：匹配展开后的标记
elif [[ "$PROMPT" =~ LDC_CMD:([a-z]+) ]]; then
  CMD="${BASH_REMATCH[1]}"
  ARGS=$(echo "$PROMPT" | grep -oP '(?<=LDC_ARGS:).*?(?=-->)' | head -1 || true)
  ARGS="${ARGS## }"
  ARGS="${ARGS%% }"
fi

if [[ -n "$CMD" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
  if [[ -f "$SCRIPT_DIR/$CMD.sh" ]]; then
    bash "$SCRIPT_DIR/$CMD.sh" "$ARGS"
    echo '{"decision": "block", "reason": "handled by ldc script"}'
    exit 0
  fi
fi

# 非 LDC 命令，放行给模型处理
echo '{"decision": "approve"}'
```

- [ ] **Step 2: 设置可执行权限**

```bash
chmod +x hooks/intercept.sh
```

- [ ] **Step 3: 验证语法**

Run: `bash -n hooks/intercept.sh`
Expected: 无输出（语法正确）

- [ ] **Step 4: 单元测试 — 策略 1 匹配**

Run: `echo '{"input":{"prompt":"/ldc:whoami"}}' | bash hooks/intercept.sh`
Expected: 先输出 whoami 脚本内容（可能因 ldc 未安装而报错），最后一行为 `{"decision": "block", "reason": "handled by ldc script"}` 或错误退出

Run: `echo '{"input":{"prompt":"hello world"}}' | bash hooks/intercept.sh`
Expected: `{"decision": "approve"}`

- [ ] **Step 5: Commit**

```bash
git add hooks/
git commit -m "feat: 添加 UserPromptSubmit hook 拦截脚本"
```

---

### Task 4: 配置 Hook 并缩减 Commands

**Files:**
- Modify: `.claude/settings.local.json`
- Modify: `commands/ship.md` (缩减)
- Modify: `commands/build.md` (缩减)
- Modify: `commands/login.md` (缩减)
- Modify: `commands/whoami.md` (缩减)
- Modify: `commands/init.md` (缩减)
- Modify: `commands/deploy.md` (缩减)
- Modify: `commands/rollback.md` (缩减)
- Modify: `commands/status.md` (缩减)
- Modify: `commands/review.md` (缩减)
- Delete: `skills/ldc-deploy/SKILL.md`

**Interfaces:**
- Consumes: `hooks/intercept.sh` 路径
- Produces: Claude Code 在加载插件时注册 hook 并识别命令列表

- [ ] **Step 1: 更新 .claude/settings.local.json**

替换全部内容为：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hook": "/bin/bash hooks/intercept.sh"
      }
    ]
  }
}
```

- [ ] **Step 2: 缩减 commands/ship.md**

替换全部内容为：

```markdown
---
name: "ship"
description: 一键构建并发布项目到未来云（测试/生产环境）
disable-model-invocation: true
category: Deploy
tags: [deploy, build, ship, ldc]
---

<!-- LDC_CMD:ship LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。用法: /ldc:ship [test|prod]
```

- [ ] **Step 3: 缩减 commands/build.md**

```markdown
---
name: "build"
description: 仅构建项目（打包），不提交发布申请
disable-model-invocation: true
category: Deploy
tags: [deploy, build, ldc]
---

<!-- LDC_CMD:build LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。用法: /ldc:build [test|prod]
```

- [ ] **Step 4: 缩减 commands/login.md**

```markdown
---
name: "login"
description: 扫码登录 ledu-cloud-cli
disable-model-invocation: true
category: Deploy
tags: [deploy, login, ldc, auth]
---

<!-- LDC_CMD:login LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。用法: /ldc:login
```

- [ ] **Step 5: 缩减 commands/whoami.md**

```markdown
---
name: "whoami"
description: 查看当前 ldc 登录用户信息
disable-model-invocation: true
category: Deploy
tags: [deploy, whoami, ldc, auth]
---

<!-- LDC_CMD:whoami LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。用法: /ldc:whoami
```

- [ ] **Step 6: 缩减 commands/init.md**

```markdown
---
name: "init"
description: 初始化项目的 .claude/deploy.json 部署配置
disable-model-invocation: true
category: Deploy
tags: [deploy, init, config, ldc]
---

<!-- LDC_CMD:init LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。用法: /ldc:init
```

- [ ] **Step 7: 缩减 commands/deploy.md**

```markdown
---
name: "deploy"
description: 发布管理 — 查看待发布列表或执行发布
disable-model-invocation: true
category: Deploy
tags: [deploy, publish, ldc]
---

<!-- LDC_CMD:deploy LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。用法: /ldc:deploy [list|publish] [test|prod]
```

- [ ] **Step 8: 缩减 commands/rollback.md**

```markdown
---
name: "rollback"
description: 回滚到已发布版本的上一版本
disable-model-invocation: true
category: Deploy
tags: [deploy, rollback, ldc]
---

<!-- LDC_CMD:rollback LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。用法: /ldc:rollback [test|prod]
```

- [ ] **Step 9: 缩减 commands/status.md**

```markdown
---
name: "status"
description: 查看项目部署状态和最近发布记录
disable-model-invocation: true
category: Deploy
tags: [deploy, status, ldc]
---

<!-- LDC_CMD:status LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。用法: /ldc:status [test|prod]
```

- [ ] **Step 10: 缩减 commands/review.md**

```markdown
---
name: "review"
description: 批量审批项目发布和团队申请
disable-model-invocation: true
category: Deploy
tags: [deploy, review, approve, ldc]
---

<!-- LDC_CMD:review LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。用法: /ldc:review
```

- [ ] **Step 11: 删除 skills/ldc-deploy/SKILL.md**

```bash
rm skills/ldc-deploy/SKILL.md
rmdir skills/ldc-deploy
rmdir skills
```

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "feat: 配置 hook 拦截，缩减 commands 为极简格式，移除 SKILL.md"
```

---

### Task 5: 集成验证

**Files:**
- 无新增文件

**Interfaces:**
- Consumes: 整个 hooks + scripts + commands 体系
- Produces: 验证通过，所有命令可正常工作

- [ ] **Step 1: 验证目录结构完整**

Run: `find scripts hooks commands -type f | sort`

Expected:
```
commands/build.md
commands/deploy.md
commands/init.md
commands/login.md
commands/review.md
commands/rollback.md
commands/ship.md
commands/status.md
commands/whoami.md
hooks/intercept.sh
scripts/_common.sh
scripts/build.sh
scripts/deploy.sh
scripts/init.sh
scripts/login.sh
scripts/review.sh
scripts/rollback.sh
scripts/ship.sh
scripts/status.sh
scripts/whoami.sh
```

- [ ] **Step 2: 验证所有脚本语法通过**

Run: `for f in scripts/*.sh hooks/*.sh; do bash -n "$f" && echo "PASS: $f" || echo "FAIL: $f"; done`

Expected: 全部 PASS

- [ ] **Step 3: 验证 hook 拦截 — LDC 命令被 block**

Run: `echo '{"input":{"prompt":"/ldc:whoami"}}' | bash hooks/intercept.sh 2>&1 | tail -1`

Expected: `{"decision": "block", "reason": "handled by ldc script"}`

- [ ] **Step 4: 验证 hook 放行 — 非 LDC 命令 approve**

Run: `echo '{"input":{"prompt":"帮我写一个函数"}}' | bash hooks/intercept.sh`

Expected: `{"decision": "approve"}`

- [ ] **Step 5: 验证策略 2 — 展开标记匹配**

Run: `echo '{"input":{"prompt":"<!-- LDC_CMD:ship LDC_ARGS:test -->\n由 hook 脚本处理"}}' | bash hooks/intercept.sh 2>&1 | tail -1`

Expected: `{"decision": "block", "reason": "handled by ldc script"}`

- [ ] **Step 6: 验证 commands 文件大小**

Run: `wc -l commands/*.md | tail -1`

Expected: 总行数 ~63（9 个文件 × 7 行）

- [ ] **Step 7: 验证 skills 目录已移除**

Run: `ls skills/ 2>&1`

Expected: 报错 `No such file or directory`

- [ ] **Step 8: 在 Claude Code 中实测**

手动在 Claude Code 中执行 `/ldc:whoami`，观察：
1. 是否直接执行脚本（终端输出带颜色）
2. 是否跳过了模型推理（无 thinking 动画、无 token 计数增长）

如果 hook 收到的是展开后内容（策略 2 生效），确认标记匹配正确。
如果 hook 收到的是原始命令（策略 1 生效），确认直接匹配正确。

记录实际生效的策略，后续可移除另一策略的代码。

- [ ] **Step 9: Commit 验证结果（如有调整）**

```bash
git add -A
git commit -m "fix: 根据实测调整 hook 匹配策略" --allow-empty
```
