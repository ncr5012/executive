#!/bin/bash
# Start or restart the Executive dashboard server

PORT=7777
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Kill existing instance
PID=$(lsof -ti tcp:$PORT 2>/dev/null)
if [ -n "$PID" ]; then
  kill $PID 2>/dev/null
  sleep 1
  echo "Killed previous server (PID $PID)"
fi

# Start server
cd "$SCRIPT_DIR"
nohup node server.js > "$SCRIPT_DIR/data/server.log" 2>&1 &
echo "Executive running at http://localhost:$PORT (PID $!)"
sleep 0.5

# Open browser (cross-platform)
if command -v xdg-open &>/dev/null; then
  xdg-open "http://localhost:$PORT" 2>/dev/null &
elif command -v open &>/dev/null; then
  open "http://localhost:$PORT"
fi
