#!/bin/bash
# PreToolUse hook: auto-registers session + checks autopilot
# Self-contained — does NOT depend on SessionStart hook

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$SESSION_ID" ] && echo '{}' && exit 0

TASK_FILE="/tmp/executive-${SESSION_ID}"
API_KEY=$(cat ~/.executive-key 2>/dev/null)
HOST=$(cat ~/.executive-host 2>/dev/null || echo "http://localhost:7778")
MACHINE=$(cat ~/.executive-machine 2>/dev/null || echo "unknown")

# If no task file yet, register this session (first tool call)
if [ ! -f "$TASK_FILE" ]; then
  CWD=$(echo "$INPUT" | grep -o '"cwd":"[^"]*"' | head -1 | cut -d'"' -f4)
  RESP=$(curl -sf --max-time 3 -X POST "$HOST/api/register" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d "{\"sessionId\":\"$SESSION_ID\",\"machine\":\"$MACHINE\",\"cwd\":\"$CWD\"}" 2>/dev/null)
  TASK_ID=$(echo "$RESP" | grep -o '"taskId":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -n "$TASK_ID" ]; then
    echo "$TASK_ID" > "$TASK_FILE"
    # Also write to CLAUDE_ENV_FILE if available
    [ -n "$CLAUDE_ENV_FILE" ] && echo "export EXEC_TASK=$TASK_ID" >> "$CLAUDE_ENV_FILE"
  else
    echo '{}' && exit 0
  fi
else
  TASK_ID=$(cat "$TASK_FILE")
fi

[ -z "$TASK_ID" ] && echo '{}' && exit 0

# Check autopilot status
RESP=$(curl -sf --max-time 2 -X POST "$HOST/api/autopilot" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{\"taskId\":\"$TASK_ID\",\"check\":\"1\"}" 2>/dev/null)

[ -z "$RESP" ] && echo '{}' && exit 0

echo "$RESP" | grep -q '"allow":true'
if [ $? -eq 0 ]; then
  # Inject "1" keystroke for tools that wait on user input
  if [ "$TOOL_NAME" = "AskUserQuestion" ] || [ "$TOOL_NAME" = "ExitPlanMode" ]; then
    # Find the TTY that Claude Code is reading from
    TARGET_PID=$PPID
    while [ "$TARGET_PID" -gt 1 ]; do
      FD0=$(readlink -f /proc/$TARGET_PID/fd/0 2>/dev/null)
      if echo "$FD0" | grep -q '/dev/pts/\|/dev/tty'; then
        (sleep 0.5 && printf '1\n' > "$FD0") &
        break
      fi
      TARGET_PID=$(ps -o ppid= -p "$TARGET_PID" 2>/dev/null | tr -d ' ')
    done
  fi
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
else
  echo '{}'
fi

exit 0
