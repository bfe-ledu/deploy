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
