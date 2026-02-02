#!/bin/bash
# PermissionRequest hook: auto-approves permission dialogs when autopilot is on

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$SESSION_ID" ] && echo '{}' && exit 0

TASK_FILE="/tmp/executive-${SESSION_ID}"
[ ! -f "$TASK_FILE" ] && echo '{}' && exit 0

TASK_ID=$(cat "$TASK_FILE")
[ -z "$TASK_ID" ] && echo '{}' && exit 0

API_KEY=$(cat ~/.executive-key 2>/dev/null)
HOST=$(cat ~/.executive-host 2>/dev/null || echo "http://localhost:7778")

RESP=$(curl -sf --max-time 2 -X POST "$HOST/api/autopilot" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{\"taskId\":\"$TASK_ID\",\"check\":\"1\"}" 2>/dev/null)

[ -z "$RESP" ] && echo '{}' && exit 0

echo "$RESP" | grep -q '"allow":true'
if [ $? -eq 0 ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
else
  echo '{}'
fi

exit 0
