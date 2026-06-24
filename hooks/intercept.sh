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

# 策略 1：直接匹配 /ldc: 前缀（用户输入未被展开）
if echo "$PROMPT" | head -1 | grep -q '^/ldc:'; then
  CMD=$(echo "$PROMPT" | head -1 | sed 's|^/ldc:\([a-z]*\).*|\1|')
  ARGS=$(echo "$PROMPT" | head -1 | sed 's|^/ldc:[a-z]* *||')
# 策略 2：匹配 <!-- LDC_CMD:xxx --> 标记
elif echo "$PROMPT" | grep -q 'LDC_CMD:'; then
  CMD=$(echo "$PROMPT" | sed -n 's/.*LDC_CMD:\([a-z]*\).*/\1/p' | head -1)
# 策略 3：匹配 <command-name>/ldc:xxx</command-name> 标签
elif echo "$PROMPT" | grep -q 'command-name>/ldc:'; then
  CMD=$(echo "$PROMPT" | sed -n 's/.*command-name>\/ldc:\([a-z]*\)<.*/\1/p' | head -1)
# 策略 4：匹配 <command-message>ldc:xxx</command-message> 标签
elif echo "$PROMPT" | grep -q 'command-message>ldc:'; then
  CMD=$(echo "$PROMPT" | sed -n 's/.*command-message>ldc:\([a-z]*\)<.*/\1/p' | head -1)
fi

if [[ -n "$CMD" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
  if [[ -f "$SCRIPT_DIR/$CMD.sh" ]]; then
    # 捕获脚本输出，显示给用户
    OUTPUT=$(bash "$SCRIPT_DIR/$CMD.sh" "$ARGS" 2>&1) || true
    # 去除 ANSI 颜色码
    CLEAN=$(echo "$OUTPUT" | sed $'s/\033\[[0-9;]*m//g')
    # 用 jq 安全转义为 JSON 字符串
    REASON=$(echo "$CLEAN" | jq -Rs '.')
    echo "{\"decision\": \"block\", \"reason\": $REASON}"
    exit 0
  fi
fi

# 非 LDC 命令，放行给模型处理
echo '{"decision": "approve"}'
