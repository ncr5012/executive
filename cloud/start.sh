#!/bin/bash
# Start or restart the Executive cloud dashboard server

PORT=7778
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
echo "Executive cloud running on 127.0.0.1:$PORT (PID $!)"
echo "Access via your nginx domain (e.g. https://executive.yourdomain.com)"
