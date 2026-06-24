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
