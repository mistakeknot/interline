# interline

Dynamic statusline renderer for Claude Code. Shows workflow phase, bead context, and Codex dispatch state.

## Overview

Reads state from multiple sources:
- **bd CLI** queries `in_progress` beads directly for title, priority, and ID
- **interphase** writes `/tmp/clavain-bead-${session_id}.json` (bead lifecycle phase)
- **Clavain** writes `/tmp/clavain-dispatch-$$.json` (Codex dispatch state)
- **Transcript** scanning detects active workflow phase from Skill invocations

## Priority Layers

1. **Dispatch** — active Codex dispatch (highest priority)
2. **Bead context** — all `in_progress` beads with priority, title, and phase
3. **Workflow phase** — last invoked skill mapped to phase name
4. **Clodex mode** — passive clodex toggle flag

## Bead Display

When `bd` is available, shows all in_progress beads with full metadata:
```
P1 Clavain-4jeg: flux-gen template... (executing), P3 Clavain-2mmc: clarify flux-drive ins...
```

- **Priority** — colored: P0 red, P1 orange, P2 yellow, P3 blue, P4 gray
- **Title** — truncated to `title_max_chars` (default 30) with ellipsis
- **Phase** — shown in parens when sideband file has phase info for that bead

Falls back to sideband-only display when `bd` is not installed.

## Configuration

All customization lives in `~/.claude/interline.json`. Every field is optional — missing keys or a missing file means built-in defaults apply.

```json
{
  "colors": {
    "clodex": [210, 216, 228, 157, 111, 183],
    "priority": [196, 208, 220, 75, 245],
    "dispatch": 214,
    "bead": 117,
    "phase": 245,
    "branch": 244
  },
  "layers": {
    "dispatch": true,
    "bead": true,
    "bead_query": true,
    "phase": true,
    "clodex": true
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
```

### Color values

ANSI 256-color codes (0-255).

- `colors.clodex` — array for per-letter rainbow, or number for single color
- `colors.priority` — array of 5 colors for P0-P4 (indexed by priority number)
- Other color keys — single number

Omit a color key to render that element without color (plain text).

### Layer toggles

Set any layer to `false` to hide it. All default to `true`.

- `layers.bead_query` — controls whether `bd list` is queried for live bead data. Disable to rely only on sideband files.

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
bash scripts/statusline.sh < /tmp/interline-test-input.json  # Smoke test (create test JSON first)
```
