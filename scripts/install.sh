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
    "clodex": [210, 216, 228, 157, 111, 183],
    "priority": [196, 208, 220, 75, 245],
    "bead": 117,
    "phase": 245,
    "branch": 244,
    "coordination": 214
  },
  "layers": {
    "dispatch": true,
    "bead": true,
    "bead_query": true,
    "phase": true,
    "clodex": true,
    "coordination": true
  },
  "labels": {
    "clodex": "Clodex",
    "dispatch_prefix": "Clodex"
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
python3 -c "
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

echo "Statusline installed at $TARGET"
echo "Settings updated: ~/.claude/settings.json"
echo "Customize: $CONFIG"
