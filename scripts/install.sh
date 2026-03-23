#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/statusline.sh"
CONFIG="$HOME/.claude/interline.json"

# Copy statusline script
cp "$SCRIPT_DIR/statusline.sh" "$TARGET"
chmod +x "$TARGET"

# Create default config if missing
if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" << 'CONF'
{
  "colors": {
    "interserve": [210, 216, 228, 157, 111, 183],
    "priority": [196, 208, 220, 75, 245],
    "bead": 117,
    "phase": 245,
    "branch": 244,
    "coordination": 214
  },
  "layers": {
    "dispatch": true,
    "bead": true,
    "bead_query": false,
    "phase": true,
    "interserve": true,
    "interserve_always": true,
    "coordination": false,
    "context": true,
    "pressure": true,
    "budget": true
  },
  "labels": {
    "interserve": "Clavain",
    "interserve_version_auto": true,
    "dispatch_prefix": "Dispatch"
  },
  "format": {
    "separator": " | ",
    "branch_separator": ":",
    "title_max_chars": 30
  }
}
CONF
  echo "Created default config at $CONFIG"
fi

# Configure settings.json
# Use jq if available, otherwise try python3 then python (Windows compat)
SETTINGS_JSON="$HOME/.claude/settings.json"
if command -v jq &>/dev/null; then
    [ ! -f "$SETTINGS_JSON" ] && echo '{}' > "$SETTINGS_JSON"
    tmp=$(mktemp)
    jq --arg cmd "$HOME/.claude/statusline.sh" '.statusLine = {"type": "command", "command": $cmd}' "$SETTINGS_JSON" > "$tmp"
    mv "$tmp" "$SETTINGS_JSON"
else
    PYTHON_CMD=""
    if command -v python3 &>/dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &>/dev/null; then
        PYTHON_CMD="python"
    fi
    if [ -n "$PYTHON_CMD" ]; then
        $PYTHON_CMD -c "
import json, os

path = os.path.expanduser('~/.claude/settings.json')
try:
    with open(path) as f:
        s = json.load(f)
except FileNotFoundError:
    s = {}

s['statusLine'] = {'type': 'command', 'command': os.path.expanduser('~/.claude/statusline.sh')}

with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
"
    else
        echo "Warning: jq or python required to configure settings.json" >&2
    fi
fi

echo "Statusline installed at $TARGET"
echo "Settings updated: ~/.claude/settings.json"
echo "Customize: $CONFIG"
