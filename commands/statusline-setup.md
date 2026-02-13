---
name: statusline-setup
description: Install or update the interline statusline script
allowed-tools: [Bash]
---

# Statusline Setup

Install the interline statusline renderer into `~/.claude/statusline.sh` and configure Claude Code to use it.

## Steps

1. Find the interline plugin directory in the cache:
```bash
INTERLINE_DIR=$(ls -d ~/.claude/plugins/cache/*/interline/*/scripts/install.sh 2>/dev/null | head -1 | xargs dirname | xargs dirname)
if [ -z "$INTERLINE_DIR" ]; then
  echo "ERROR: interline plugin not found in cache. Install with: claude plugin install interline@interagency-marketplace"
  exit 1
fi
echo "Found interline at: $INTERLINE_DIR"
```

2. Run the install script:
```bash
bash "$INTERLINE_DIR/scripts/install.sh"
```

3. Verify the installation:
```bash
echo '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/test"}}' | ~/.claude/statusline.sh
```

4. Report success or failure to the user. The statusline will be active in the next Claude Code session.
