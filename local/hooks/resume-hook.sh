#!/bin/bash
# UserPromptSubmit hook: flips task back to "working" when user sends a new message

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$SESSION_ID" ] && exit 0

TASK_FILE="/tmp/executive-${SESSION_ID}"
[ ! -f "$TASK_FILE" ] && exit 0

TASK_ID=$(cat "$TASK_FILE")
[ -z "$TASK_ID" ] && exit 0

API_KEY=$(cat ~/.executive-key 2>/dev/null)
HOST=$(cat ~/.executive-host 2>/dev/null || echo "http://localhost:7777")

curl -sf --max-time 2 -X POST "$HOST/api/resume" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{\"taskId\":\"$TASK_ID\"}" >/dev/null 2>&1

exit 0
