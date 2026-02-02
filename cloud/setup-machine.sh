#!/bin/bash
# setup-machine.sh — Run this on any machine to configure it for Executive (cloud)
# Usage: ./setup-machine.sh [machine-name] [dashboard-host]
#
# On the server machine (where .env exists): auto-configures everything
# On remote machines: prompts for host URL and API key
#
# Examples:
#   ./setup-machine.sh                                          # auto-detect server or prompt
#   ./setup-machine.sh devbox https://executive.vibeotter.dev   # remote machine

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACHINE="${1:-local}"
HOST="${2:-}"
ENV_FILE="$SCRIPT_DIR/.env"
IS_SERVER=false

# Detect if we're on the server machine
if [ -f "$ENV_FILE" ]; then
  IS_SERVER=true
fi

echo "=== Executive Cloud Machine Setup ==="
echo "  Executive dir: $SCRIPT_DIR"
echo "  Machine name:  $MACHINE"
if $IS_SERVER; then
  echo "  Mode:          SERVER (found .env)"
else
  echo "  Mode:          REMOTE CLIENT"
fi
echo ""

# 1. Install node dependencies if needed
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
  echo "[1/5] Installing dependencies..."
  cd "$SCRIPT_DIR" && npm install --production
else
  echo "[1/5] Dependencies already installed."
fi

# 2. Run setup.js on server machine (generates .env, API key, password hash)
if $IS_SERVER; then
  echo "[2/5] Running setup.js..."
  cd "$SCRIPT_DIR" && node setup.js
else
  echo "[2/5] Skipping setup.js (remote machine)."
fi

# 3. Write machine-specific config to home directory
echo "[3/5] Writing machine config..."

# Machine identity
echo "$MACHINE" > ~/.executive-machine
echo "  Wrote ~/.executive-machine = $MACHINE"

# Dashboard host
if $IS_SERVER; then
  # Server machine: hooks talk directly to localhost, no nginx round-trip
  HOST="http://127.0.0.1:7778"
  echo "$HOST" > ~/.executive-host
  echo "  Wrote ~/.executive-host = $HOST (localhost — server machine)"
else
  # Remote machine: need the public URL
  if [ -z "$HOST" ]; then
    echo -n "  Dashboard host URL (e.g. https://executive.yourdomain.com): "
    read HOST
    if [ -z "$HOST" ]; then
      echo "  Error: host URL is required for remote setup."
      exit 1
    fi
  fi
  # Validate protocol prefix
  if ! echo "$HOST" | grep -qE '^https?://'; then
    echo "  Warning: host URL missing protocol, adding https://"
    HOST="https://$HOST"
  fi
  # Strip trailing slash
  HOST="${HOST%/}"
  echo "$HOST" > ~/.executive-host
  echo "  Wrote ~/.executive-host = $HOST"
fi

# 4. API key
if $IS_SERVER; then
  # Read directly from .env — single source of truth
  API_KEY=$(grep '^EXECUTIVE_API_KEY=' "$ENV_FILE" | cut -d'=' -f2)
  if [ -z "$API_KEY" ]; then
    echo "  Error: EXECUTIVE_API_KEY not found in .env. Run setup.js first."
    exit 1
  fi
  echo "$API_KEY" > ~/.executive-key
  echo "[4/5] Synced API key from .env to ~/.executive-key"
else
  # Remote machine: always prompt so key stays in sync with server
  echo ""
  if [ -f ~/.executive-key ]; then
    echo "  Current API key: $(cat ~/.executive-key | cut -c1-8)..."
  fi
  echo "  On the server, run: grep EXECUTIVE_API_KEY .env"
  echo -n "  Paste the API key from the cloud server's .env file: "
  read API_KEY
  if [ -z "$API_KEY" ]; then
    echo "  Error: API key is required."
    exit 1
  fi
  echo "$API_KEY" > ~/.executive-key
  echo "[4/5] Wrote ~/.executive-key"
fi

# 5. Configure Claude Code hooks globally
echo "[5/5] Configuring Claude Code hooks..."

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
  PermissionRequest: [{
    matcher: '',
    hooks: [{ type: 'command', command: hooksDir + '/permission-hook.sh', timeout: 5 }]
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
if $IS_SERVER; then
  echo "  Dashboard: open your nginx domain in a browser."
else
  echo "  Dashboard: open $HOST in a browser."
fi
echo ""
