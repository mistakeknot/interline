# interline — Vision and Philosophy

**Version:** 0.1.0
**Last updated:** 2026-02-28

## What interline Is

interline is a dynamic statusline renderer for Claude Code. It reads live state from five independent sources — the Beads task system (`bd` CLI), the Interphase sideband, Clavain dispatch files, Interlock coordination signals, and the session transcript — and composes them into a single line of prioritized context. The output reflects what is actually happening: which bead is in progress, what phase it is in, whether Clavain has an active dispatch, and whether multi-agent coordination is live. One script produces one line, updated every time Claude Code refreshes the status indicator.

The architecture is a layered priority system. Dispatch state takes precedence over coordination, which takes precedence over bead context, which takes precedence over workflow phase. Each layer is independently toggleable. The renderer is stateless: it reads stdin JSON from Claude Code, queries external state on each invocation, and emits colored ANSI text. There is no daemon, no background process, and no persistent state of its own.

## Why This Exists

Agent workflow state is largely invisible. A session could be mid-sprint, blocked on a bead, dispatched to Clavain, or coordinating across agents — and none of that is visible at a glance. interline makes the invisible legible without requiring the agent or the human to narrate it. The statusline is live evidence of what the system is doing, not a report the system generates after the fact.

## Design Principles

1. **Evidence over narrative.** The statusline reflects current state derived from durable signals (bead records, dispatch files, sideband JSON). It does not summarize what happened — it shows what is happening now.

2. **Composition over integration.** interline reads from five independent sources and composes their output into one display. It does not own any of those sources, does not write to them, and does not break if any one is absent. Each source is optional; the renderer degrades gracefully.

3. **Mechanism, not policy.** The renderer surfaces whatever signals exist. It does not decide which bead matters most, does not enforce workflow rules, and does not change behavior based on what it displays. Signal relevance is determined by the priority layer ordering, not by interline's judgment.

4. **Low distraction.** Every field on the statusline competes for attention. The default configuration shows the minimum useful set. Layers can be disabled individually. Long titles are truncated. The goal is at-a-glance clarity — one read, no parsing.

5. **Fail open.** Missing files, absent CLIs, and empty sideband directories are all normal. The renderer emits whatever it can find and omits the rest silently. A partial statusline is always better than no statusline.

## Scope

**Does:**
- Render bead context (ID, priority, title, phase) from live `bd list` queries and sideband files
- Show active Clavain dispatch state and Codex dispatch label
- Display Interlock coordination status when `INTERMUTE_AGENT_ID` is set
- Detect workflow phase from transcript skill invocations
- Show context window usage percentage with color thresholds
- Read all display configuration from `~/.claude/interline.json`

**Does not:**
- Own or write to any of the state sources it reads
- Enforce workflow policy or gate any actions
- Run as a background process or maintain its own state
- Change behavior based on what it displays

## Direction

- Expand signal coverage as new Demarch subsystems produce structured sideband output
- Improve phase detection accuracy as transcript patterns stabilize across skill invocations
- Track context window pressure trends across turns to surface early warning before critical thresholds
