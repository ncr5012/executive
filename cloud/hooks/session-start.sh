#!/bin/bash
# SessionStart hook: registers session with Executive dashboard
# This is a backup — autopilot-hook.sh also handles registration on first tool call

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
SOURCE=$(echo "$INPUT" | grep -o '"source":"[^"]*"' | head -1 | cut -d'"' -f4)
CWD=$(echo "$INPUT" | grep -o '"cwd":"[^"]*"' | head -1 | cut -d'"' -f4)

[ "$SOURCE" != "startup" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

API_KEY=$(cat ~/.executive-key 2>/dev/null)
MACHINE=$(cat ~/.executive-machine 2>/dev/null || echo "unknown")
HOST=$(cat ~/.executive-host 2>/dev/null || echo "http://localhost:7778")

RESP=$(curl -sf --max-time 3 -X POST "$HOST/api/register" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{\"sessionId\":\"$SESSION_ID\",\"machine\":\"$MACHINE\",\"cwd\":\"$CWD\"}" 2>/dev/null)

TASK_ID=$(echo "$RESP" | grep -o '"taskId":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$TASK_ID" ]; then
  echo "$TASK_ID" > "/tmp/executive-${SESSION_ID}"
  [ -n "$CLAUDE_ENV_FILE" ] && echo "export EXEC_TASK=$TASK_ID" >> "$CLAUDE_ENV_FILE"
fi

exit 0
