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

## Configuration

The install creates `~/.claude/interline.json` with defaults. Users can customize:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `colors.clodex` | array or number | `[210,216,228,157,111,183]` | Per-letter rainbow (array) or single color (number) for the Clodex label |
| `colors.dispatch` | number | _(none)_ | ANSI 256-color for dispatch status text |
| `colors.bead` | number | _(none)_ | ANSI 256-color for bead context text |
| `colors.phase` | number | _(none)_ | ANSI 256-color for workflow phase text |
| `colors.branch` | number | _(none)_ | ANSI 256-color for git branch name |
| `layers.dispatch` | boolean | `true` | Show Codex dispatch state |
| `layers.bead` | boolean | `true` | Show bead context (ID + phase) |
| `layers.phase` | boolean | `true` | Show workflow phase from transcript |
| `layers.clodex` | boolean | `true` | Show clodex mode indicator |
| `labels.clodex` | string | `"Clodex"` | Text for the clodex mode rainbow label |
| `labels.dispatch_prefix` | string | `"Clodex"` | Prefix before dispatch task name |
| `format.separator` | string | `" \| "` | Separator between status segments |
| `format.branch_separator` | string | `":"` | Separator between project name and branch |

All fields are optional. Missing keys use built-in defaults. Delete the file to reset everything.

### Examples

Disable bead context and make phase labels red:
```json
{
  "layers": { "bead": false },
  "colors": { "phase": 196 }
}
```

Use a single teal color for the Clodex label:
```json
{
  "colors": { "clodex": 44 }
}
```
