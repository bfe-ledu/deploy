#!/bin/bash

# LDC Command Hook Interceptor
# 拦截 /ldc:* 斜杠命令，直接执行对应 shell 脚本，绕过模型推理。
#
# 双重匹配策略：
# 1. 原始命令匹配 — prompt 以 /ldc: 开头（命令未被展开）
# 2. 展开标记匹配 — prompt 包含 <!-- LDC_CMD:xxx -->（命令已展开为 markdown）

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.input.prompt // empty')

CMD=""
ARGS=""

# 策略 1：直接匹配 /ldc: 前缀
if [[ "$PROMPT" =~ ^/ldc:([a-z]+)(\ .*)? ]]; then
  CMD="${BASH_REMATCH[1]}"
  ARGS="${BASH_REMATCH[2]## }"
# 策略 2：匹配展开后的标记
elif [[ "$PROMPT" =~ LDC_CMD:([a-z]+) ]]; then
  CMD="${BASH_REMATCH[1]}"
  if [[ "$PROMPT" =~ LDC_ARGS:([^-]+)-- ]]; then
    ARGS="${BASH_REMATCH[1]}"
  fi
  ARGS="${ARGS## }"
  ARGS="${ARGS%% }"
fi

if [[ -n "$CMD" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
  if [[ -f "$SCRIPT_DIR/$CMD.sh" ]]; then
    bash "$SCRIPT_DIR/$CMD.sh" "$ARGS"
    echo '{"decision": "block", "reason": "handled by ldc script"}'
    exit 0
  fi
fi

# 非 LDC 命令，放行给模型处理
echo '{"decision": "approve"}'
