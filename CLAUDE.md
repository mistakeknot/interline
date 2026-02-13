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

## Files

- `scripts/statusline.sh` — the renderer (reads stdin JSON, outputs status text)
- `scripts/install.sh` — copies script to `~/.claude/` and configures `settings.json`
- `commands/statusline-setup.md` — `/interline:statusline-setup` command

## Quick Commands

```bash
bash -n scripts/statusline.sh    # Syntax check
bash -n scripts/install.sh       # Syntax check
echo '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/test"}}' | bash scripts/statusline.sh
```
