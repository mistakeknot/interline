# interline

Dynamic statusline renderer for Claude Code. Shows workflow phase, bead context, and Codex dispatch state.

## Overview

Reads state from `/tmp/` sideband files written by companion plugins:
- **Clavain** writes `/tmp/clavain-dispatch-$$.json` (Codex dispatch state)
- **interphase** writes `/tmp/clavain-bead-${session_id}.json` (bead lifecycle context)
- **Transcript** scanning detects active workflow phase from Skill invocations

## Priority Layers

1. **Dispatch** — active Codex dispatch (highest priority)
2. **Bead context** — current bead ID and phase
3. **Workflow phase** — last invoked skill mapped to phase name
4. **Clodex mode** — passive clodex toggle flag

## Configuration

All customization lives in `~/.claude/interline.json`. Every field is optional — missing keys or a missing file means built-in defaults apply.

```json
{
  "colors": {
    "clodex": [210, 216, 228, 157, 111, 183],
    "dispatch": 214,
    "bead": 117,
    "phase": 245,
    "branch": 244
  },
  "layers": {
    "dispatch": true,
    "bead": true,
    "phase": true,
    "clodex": true
  },
  "labels": {
    "clodex": "Clodex",
    "dispatch_prefix": "Clodex"
  },
  "format": {
    "separator": " | ",
    "branch_separator": ":"
  }
}
```

### Color values

ANSI 256-color codes (0-255). `colors.clodex` accepts either:
- **Array** — per-letter rainbow (cycles through array for each character)
- **Number** — single color for the entire label

Other color keys accept a number. Omit a color key to render that element without color (plain text).

### Layer toggles

Set any layer to `false` to hide it. All default to `true`.

### Agent guidelines

When helping users customize the statusline, read `~/.claude/interline.json` first. Respect existing config — merge changes, don't overwrite the file. Example: to disable a layer, read the file, set the key, write it back.

## Files

- `scripts/statusline.sh` — the renderer (reads stdin JSON, outputs status text)
- `scripts/install.sh` — copies script to `~/.claude/`, creates default config, configures `settings.json`
- `commands/statusline-setup.md` — `/interline:statusline-setup` command

## Quick Commands

```bash
bash -n scripts/statusline.sh    # Syntax check
bash -n scripts/install.sh       # Syntax check
echo '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/test"}}' | bash scripts/statusline.sh
```
