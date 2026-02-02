#!/bin/bash
# Stop hook: notifies dashboard this Claude session finished
# Reads task ID from temp file (written by autopilot-hook on first tool call)

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$SESSION_ID" ] && exit 0

TASK_FILE="/tmp/executive-${SESSION_ID}"
[ ! -f "$TASK_FILE" ] && exit 0

TASK_ID=$(cat "$TASK_FILE")
[ -z "$TASK_ID" ] && exit 0

API_KEY=$(cat ~/.executive-key 2>/dev/null)
HOST=$(cat ~/.executive-host 2>/dev/null || echo "http://localhost:7777")

curl -sf --max-time 2 -X POST "$HOST/api/complete" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{\"taskId\":\"$TASK_ID\"}" >/dev/null 2>&1

# Do NOT delete temp file — SessionEnd needs it to clean up the task

exit 0
