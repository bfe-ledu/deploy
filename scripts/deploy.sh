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
