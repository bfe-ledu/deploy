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
