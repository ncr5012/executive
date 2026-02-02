#!/bin/bash
# SessionEnd hook: removes task from dashboard when session exits (ctrl+c, /exit, etc)

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$SESSION_ID" ] && exit 0

TASK_FILE="/tmp/executive-${SESSION_ID}"
[ ! -f "$TASK_FILE" ] && exit 0

TASK_ID=$(cat "$TASK_FILE")
[ -z "$TASK_ID" ] && exit 0

API_KEY=$(cat ~/.executive-key 2>/dev/null)
HOST=$(cat ~/.executive-host 2>/dev/null || echo "http://localhost:7778")

# Delete the task from dashboard
curl -sf --max-time 2 -X DELETE "$HOST/api/tasks/$TASK_ID" \
  -H "X-API-Key: $API_KEY" >/dev/null 2>&1

rm -f "$TASK_FILE"

exit 0
