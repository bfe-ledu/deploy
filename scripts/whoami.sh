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
