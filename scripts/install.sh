#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/statusline.sh"

# Copy statusline script
cp "$SCRIPT_DIR/statusline.sh" "$TARGET"
chmod +x "$TARGET"

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
