# Brainstorm: interline Statusline Improvements

**Date:** 2026-02-12
**Status:** Complete — ready for planning

## What We're Building

Enhance the interline statusline plugin with two core improvements:

1. **Live bead display** — Always show the bead(s) the user is actively working on, not just when phase tracking fires
2. **Richer bead info** — Show priority, title preview, and phase per bead with colored priority dots
3. **Multi-bead support** — Display all in_progress beads comma-separated

## Why This Approach

### Live bead query via `bd`

Currently, bead context only appears when `advance_phase` writes a sideband file to `/tmp/clavain-bead-{session_id}.json`. This means:
- No bead shows if the user starts working without `/lfg`
- No bead shows until the first phase transition
- Only ONE bead is tracked (the last one passed to `advance_phase`)

**Solution:** Query `bd list --status=in_progress --json` directly from the statusline script. This gives real-time, complete visibility into all active work.

**Hybrid approach:** Prefer the sideband file when it exists (it has phase info that `bd list` doesn't). Fall back to `bd list` for beads not in the sideband.

### Full bead info display

Show each bead as: `P1 Clavain-4jeg: flux-gen template... (executing)`

- Colored priority dot (P0=red, P1=orange, P2=yellow, P3=blue, P4=gray)
- Bead ID
- Title truncated to ~30 chars
- Phase in parens (if available from sideband)

### Visual refinements

Keep the current `[Model] Project:branch | context` format but refine:
- Better color defaults for priorities
- Consistent separator usage
- Title truncation with ellipsis

## Key Decisions

1. **bd query adds ~50ms per statusline render** — acceptable; Claude Code already tolerates 100ms+ for statusline commands
2. **Sideband takes priority over bd query** — sideband has phase info; bd query has title/priority. Merge both when both exist.
3. **No cap on displayed beads** — show all in_progress beads, comma-separated. If it gets too long, the terminal handles wrapping.
4. **bd binary must be available** — if `bd` isn't installed, gracefully fall back to sideband-only (current behavior)
5. **Work in `/root/projects/interline/`** — this is the interline plugin repo, not Clavain

## Open Questions

None — ready for planning.

## Example Output

**Single bead (with phase tracking):**
```
[Claude] Clavain:main | P1 Clavain-4jeg: flux-gen template... (executing) | Reviewing
```

**Multiple beads (mixed sources):**
```
[Claude] Clavain:main | P1 Clavain-4jeg: flux-gen template... (executing), P3 Clavain-2mmc: clarify flux-drive ins...
```

**No beads in_progress:**
```
[Claude] Clavain:main | Reviewing
```

**No phase, no beads (minimal):**
```
[Claude] Clavain:main
```
