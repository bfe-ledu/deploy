#!/bin/bash
source "$(dirname "$0")/_common.sh"

heading "LDC Review"
preflight

info "进入审批管理..."
ldc review
