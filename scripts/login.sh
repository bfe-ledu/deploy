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
