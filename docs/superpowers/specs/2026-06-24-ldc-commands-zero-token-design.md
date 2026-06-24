# LDC Commands Zero-Token 优化设计

> 将所有 `/ldc:*` 斜杠命令的执行从「模型推理驱动」迁移为「Hook + Shell 脚本直接执行」，实现零 token 消耗。

**日期**: 2026-06-24  
**状态**: Draft  
**作者**: bfe-ledu

---

## 1. 目标

| 目标 | 度量 |
|------|------|
| 命令执行零 token 消耗 | 每次 `/ldc:*` 执行不触发模型推理 |
| 减少 context window 占用 | commands + skills 从 ~580 行降至 ~45 行 |
| 保留斜杠命令 UX | 用户仍通过 `/ldc:ship test` 调用 |
| 保持功能完整 | 前置检查、环境选择、二次确认、错误处理全保留 |

---

## 2. 架构

### 2.1 执行流程

```
用户输入 /ldc:ship test
  → Claude Code 展开命令（替换 $ARGUMENTS）
  → UserPromptSubmit hook 触发
  → hooks/intercept.sh 检测 LDC 命令标记
  → 执行 scripts/ship.sh "test"
  → 返回 {"decision": "block"} 阻止模型处理
  → 终端显示脚本输出
  → token 消耗：0
```

### 2.2 目录结构

```
deploy/
├── .claude-plugin/
│   └── plugin.json              # 不变
├── .claude/
│   └── settings.local.json      # hook 配置
├── hooks/
│   └── intercept.sh             # hook 入口，路由到对应脚本
├── scripts/
│   ├── _common.sh               # 共享函数
│   ├── login.sh
│   ├── whoami.sh
│   ├── init.sh
│   ├── ship.sh
│   ├── build.sh
│   ├── deploy.sh
│   ├── rollback.sh
│   ├── status.sh
│   └── review.sh
├── commands/                     # 极简化：仅 frontmatter + 标记
│   └── *.md
└── skills/
    └── ldc-deploy/SKILL.md      # 移除（或保留为开发者参考，不影响 context）
```

---

## 3. Hook 拦截机制

### 3.1 配置

`.claude/settings.local.json`:

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

### 3.2 拦截脚本 `hooks/intercept.sh`

从 stdin 读取 JSON 格式的 hook input，检测是否为 LDC 命令，决定 block 或 approve。

**检测策略**：由于 slash command 可能在 hook 触发前已展开为 markdown 内容，采用双重匹配：

1. **原始命令匹配**：检测 prompt 是否以 `/ldc:` 开头（未展开情况）
2. **展开标记匹配**：在每个 command.md 的 body 中插入标记 `<!-- LDC_CMD:ship -->`，hook 检测此标记（已展开情况）

```bash
#!/bin/bash
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.input.prompt // empty')

# 策略 1：直接匹配 /ldc: 前缀
if [[ "$PROMPT" =~ ^/ldc:([a-z]+)(\ .*)? ]]; then
  CMD="${BASH_REMATCH[1]}"
  ARGS="${BASH_REMATCH[2]## }"
# 策略 2：匹配展开后的标记
elif [[ "$PROMPT" =~ LDC_CMD:([a-z]+) ]]; then
  CMD="${BASH_REMATCH[1]}"
  # 从展开内容中提取 $ARGUMENTS 的值
  ARGS=$(echo "$PROMPT" | grep -oP '(?<=LDC_ARGS:).*?(?=-->)' || true)
  ARGS="${ARGS## }"
fi

if [[ -n "${CMD:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
  if [[ -f "$SCRIPT_DIR/$CMD.sh" ]]; then
    bash "$SCRIPT_DIR/$CMD.sh" "$ARGS"
    echo '{"decision": "block", "reason": "handled by ldc script"}'
    exit 0
  fi
fi

echo '{"decision": "approve"}'
```

### 3.3 Command Markdown 标记格式

每个 `commands/*.md` 缩减为：

```markdown
---
name: "ship"
description: 一键构建并发布项目到未来云（测试/生产环境）
disable-model-invocation: true
category: Deploy
tags: [deploy, build, ship, ldc]
---

<!-- LDC_CMD:ship LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。
```

---

## 4. Shell 脚本实现

### 4.1 共享函数 `scripts/_common.sh`

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

### 4.2 命令脚本

#### `scripts/ship.sh`

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

#### `scripts/build.sh`

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

#### `scripts/login.sh`

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

#### `scripts/whoami.sh`

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

#### `scripts/init.sh`

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

#### `scripts/deploy.sh`

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

#### `scripts/rollback.sh`

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

#### `scripts/status.sh`

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

#### `scripts/review.sh`

```bash
#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Review"
preflight

info "进入审批管理..."
ldc review
```

---

## 5. 清理变更

### 5.1 commands/*.md 统一模板

每个命令文件缩减为：

```markdown
---
name: "<command>"
description: <一行描述>
disable-model-invocation: true
category: Deploy
tags: [deploy, ldc, ...]
---

<!-- LDC_CMD:<command> LDC_ARGS:$ARGUMENTS -->
由 hook 脚本处理，无需模型参与。
```

### 5.2 skills/ldc-deploy/SKILL.md

移除。该文件内容已完整迁移到 shell 脚本中。如需保留开发者参考，可移动到 `docs/` 目录。

---

## 6. 兼容性与风险

| 风险 | 缓解策略 |
|------|----------|
| Hook 收到的是展开后的 markdown | 双重匹配策略（原始前缀 + 内嵌标记） |
| Shell 交互（select/read）在某些 IDE 终端不可用 | 命令参数优先，交互为 fallback |
| ldc 命令超时（构建 10min+） | shell 无需设置 timeout，用户可 Ctrl+C |
| Hook 机制未来变更 | 脚本逻辑独立，可随时回退到 command 模式 |

---

## 7. 迁移步骤

1. 创建 `scripts/_common.sh` + 9 个命令脚本
2. 创建 `hooks/intercept.sh`
3. 更新 `.claude/settings.local.json` 添加 hook 配置
4. 缩减 `commands/*.md` 为极简格式
5. 移除 `skills/ldc-deploy/SKILL.md`
6. 本地验证：执行 `/ldc:whoami` 确认 hook 拦截生效
7. 如 hook 收到的是展开内容，调整匹配策略
