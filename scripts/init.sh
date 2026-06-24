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
