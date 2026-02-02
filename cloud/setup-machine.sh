#!/bin/bash
# setup-machine.sh — Run this on any machine to configure it for Executive (cloud)
# Usage: ./setup-machine.sh [machine-name] [dashboard-host]
#
# Examples:
#   ./setup-machine.sh                                          # defaults: machine="local", host from prompt
#   ./setup-machine.sh devbox https://executive.vibeotter.dev   # custom machine + remote host

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACHINE="${1:-local}"
HOST="${2:-}"

# If no host provided, prompt for it
if [ -z "$HOST" ]; then
  echo -n "Dashboard host URL (e.g. https://executive.yourdomain.com): "
  read HOST
  if [ -z "$HOST" ]; then
    echo "Error: host URL is required for cloud setup."
    exit 1
  fi
fi

echo "=== Executive Cloud Machine Setup ==="
echo "  Executive dir: $SCRIPT_DIR"
echo "  Machine name:  $MACHINE"
echo "  Dashboard host: $HOST"
echo ""

# 1. Install node dependencies if needed (only needed on the server itself)
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
  echo "[1/4] Installing dependencies..."
  cd "$SCRIPT_DIR" && npm install --production
else
  echo "[1/4] Dependencies already installed."
fi

# 2. Write machine-specific config to home directory
echo "[2/4] Writing machine config..."

# Machine identity
echo "$MACHINE" > ~/.executive-machine
echo "  Wrote ~/.executive-machine = $MACHINE"

# Dashboard host
echo "$HOST" > ~/.executive-host
echo "  Wrote ~/.executive-host = $HOST"

# 3. API key — prompt if not already set
if [ ! -f ~/.executive-key ]; then
  echo ""
  echo "  No API key found at ~/.executive-key."
  echo -n "  Paste the API key from the cloud server's .env file: "
  read API_KEY
  if [ -z "$API_KEY" ]; then
    echo "  Error: API key is required."
    exit 1
  fi
  echo "$API_KEY" > ~/.executive-key
  echo "  Wrote ~/.executive-key"
else
  echo "[3/4] API key already set at ~/.executive-key"
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
