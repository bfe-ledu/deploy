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
