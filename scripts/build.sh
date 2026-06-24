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
