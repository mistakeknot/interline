# interline — Agent Guide

Dynamic statusline renderer for Claude Code. Shows workflow phase, bead context, and Codex dispatch state.

## Architecture

Reads state from multiple sources:
- **bd CLI** queries `in_progress` beads directly for title, priority, and ID
- **interphase** writes `~/.interband/interphase/bead/${session_id}.json`
- **Clavain** writes `/tmp/clavain-dispatch-$$.json` plus sideband at `~/.interband/clavain/dispatch/${pid}.json`
- **interlock** writes `/var/run/intermute/signals/{project-slug}-{agent-id}.jsonl` and mirrors to `~/.interband/interlock/coordination/{project-slug}-{agent-id}.json`
- **Transcript** scanning detects active workflow phase from Skill invocations

## Priority Layers

1. **Dispatch** — active Codex dispatch (highest priority)
2. **Coordination** — multi-agent coordination status from interlock signal files
3. **Bead context** — all `in_progress` beads with priority, title, and phase
4. **Workflow phase** — last invoked skill mapped to phase name
5. **Interserve mode** — passive interserve toggle flag

## Bead Display

Shows all in_progress beads with full metadata:
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
    "interserve": [210, 216, 228, 157, 111, 183],
    "priority": [196, 208, 220, 75, 245],
    "dispatch": 214, "bead": 117, "phase": 245,
    "branch": 244, "coordination": 214,
    "context": 245, "context_warn": 220, "context_critical": 196
  },
  "layers": {
    "dispatch": true, "bead": true, "bead_query": false,
    "phase": true, "interserve": true, "interserve_always": true,
    "coordination": false, "context": true, "pressure": true, "budget": true
  },
  "labels": {
    "interserve": "Clavain",
    "interserve_version_auto": true,
    "dispatch_prefix": "Dispatch"
  },
  "format": {
    "separator": " | ", "branch_separator": ":",
    "title_max_chars": 30
  }
}
```

### Color values

ANSI 256-color codes (0-255). `colors.interserve` — array for per-letter rainbow, or number for single color. `colors.priority` — array of 5 for P0-P4. Omit a key to render plain text.

### Layer toggles

Set any layer to `false` to hide it. Notable:
- `layers.bead_query` — controls `bd list` queries (disable to rely on sideband files only)
- `layers.coordination` — interlock signals (requires `INTERMUTE_AGENT_ID` env var)
- `layers.context` — context window usage % (reads from stdin JSON)
- `layers.interserve_always` — branding label always visible vs gated by clodex-toggle

### Agent guidelines

When helping users customize, read `~/.claude/interline.json` first. Merge changes — don't overwrite the file.

## Files

- `scripts/statusline.sh` — the renderer (reads stdin JSON, outputs status text)
- `scripts/install.sh` — copies script, creates default config, configures settings.json
- `commands/statusline-setup.md` — `/interline:statusline-setup` command
