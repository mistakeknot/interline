# interline

Dynamic statusline for Claude Code.

## What This Does

interline renders a persistent statusline showing what's happening in your session without you having to check manually. It integrates with multiple sources — beads (active work items with priority coloring), interphase (workflow phase), interlock (multi-agent coordination status), and Clavain dispatch (Codex agent state) — and compresses it all into a single line.

Priority coloring makes triage visible at a glance: P0 red, P1 orange, P2 yellow, P3 blue, P4 gray. Each in-progress bead shows its title and phase alongside the priority indicator.

## Installation

```bash
/plugin install interline
```

Then run the setup command to install the statusline renderer:

```
/interline:statusline-setup
```

## Configuration

JSON config at `~/.claude/interline.json` controls colors, layer toggles, labels, and format. The statusline reads from multiple sources and falls back gracefully when optional integrations aren't available — if you don't use interphase, that layer just doesn't render.

## Architecture

```
scripts/
  statusline.sh        Main renderer (reads beads, sideband files, dispatch state)
  install.sh           Installs into Claude Code settings
commands/
  statusline-setup.md  Setup command
```

The statusline is not a traditional plugin skill — it's configured as a Claude Code status provider and runs on every prompt.
