#!/bin/bash
# setup-machine.sh — Run this on any new machine to configure it for Executive
# Usage: ./setup-machine.sh [machine-name] [dashboard-host]
#
# Examples:
#   ./setup-machine.sh                           # defaults: machine="local", host="http://localhost:7777"
#   ./setup-machine.sh devbox                    # custom machine name
#   ./setup-machine.sh laptop http://10.0.0.5:7777  # remote dashboard

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACHINE="${1:-local}"
HOST="${2:-http://localhost:7777}"

echo "=== Executive Machine Setup ==="
echo "  Executive dir: $SCRIPT_DIR"
echo "  Machine name:  $MACHINE"
echo "  Dashboard host: $HOST"
echo ""

# 1. Install node dependencies if needed
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
  echo "[1/4] Installing dependencies..."
  cd "$SCRIPT_DIR" && npm install --production
else
  echo "[1/4] Dependencies already installed."
fi

# 2. Run setup.js to generate API key + data files
echo "[2/4] Running setup.js..."
cd "$SCRIPT_DIR" && node setup.js

# 3. Write machine-specific config to home directory
echo "[3/4] Writing machine config..."

# Machine identity
echo "$MACHINE" > ~/.executive-machine
echo "  Wrote ~/.executive-machine = $MACHINE"

# Dashboard host
echo "$HOST" > ~/.executive-host
echo "  Wrote ~/.executive-host = $HOST"

# API key was already written by setup.js, but if connecting to a remote
# dashboard, the user needs to manually copy the key from the server.
if [ "$HOST" != "http://localhost:7777" ]; then
  echo ""
  echo "  NOTE: You are pointing at a remote dashboard ($HOST)."
  echo "  Make sure ~/.executive-key on this machine matches the server's data/key.txt."
  echo "  You can copy it with: scp server:$SCRIPT_DIR/data/key.txt ~/.executive-key"
fi

# 4. Configure Claude Code hooks globally
echo "[4/4] Configuring Claude Code hooks..."

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"

# Make hook scripts executable
chmod +x "$SCRIPT_DIR/hooks/"*.sh

# Build hooks JSON using node (safer than sed for JSON manipulation)
node -e "
const fs = require('fs');
const settingsPath = '$CLAUDE_SETTINGS';
const hooksDir = '$SCRIPT_DIR/hooks';

let settings = {};
if (fs.existsSync(settingsPath)) {
  try { settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); }
  catch(e) { console.error('  Warning: could not parse existing settings.json, backing up...'); }
}

// Backup existing settings
if (Object.keys(settings).length > 0) {
  fs.writeFileSync(settingsPath + '.bak', JSON.stringify(settings, null, 2));
}

settings.hooks = {
  SessionStart: [{
    matcher: '',
    hooks: [{ type: 'command', command: hooksDir + '/session-start.sh', timeout: 5 }]
  }],
  PreToolUse: [{
    matcher: '',
    hooks: [{ type: 'command', command: hooksDir + '/autopilot-hook.sh', timeout: 5 }]
  }],
  Stop: [{
    hooks: [{ type: 'command', command: hooksDir + '/stop-hook.sh', timeout: 5 }]
  }],
  UserPromptSubmit: [{
    hooks: [{ type: 'command', command: hooksDir + '/resume-hook.sh', timeout: 5 }]
  }],
  SessionEnd: [{
    matcher: '',
    hooks: [{ type: 'command', command: hooksDir + '/session-end.sh', timeout: 5 }]
  }]
};

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
console.log('  Wrote hooks to ' + settingsPath);
"

echo ""
echo "=== Setup complete ==="
echo "  Start the dashboard:  cd $SCRIPT_DIR && ./start.sh"
echo "  Open a new Claude session — it will auto-register with the dashboard."
echo ""
echo "  To verify: open $HOST in a browser after starting the server."
