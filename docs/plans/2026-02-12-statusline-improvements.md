# Plan: Interline Statusline Improvements

**Date:** 2026-02-12
**Brainstorm:** `docs/brainstorms/2026-02-12-statusline-improvements-brainstorm.md`
**Scope:** Modify `scripts/statusline.sh`, update config defaults, update CLAUDE.md

## Changes

### 1. Add Layer 1.5b: Live bead query via `bd`

**File:** `scripts/statusline.sh`

After the existing Layer 1.5 (sideband bead check), add a new section that queries `bd list --status=in_progress --json` to get all active beads with full metadata.

**Logic:**
1. Check if `bd` is available (`command -v bd`)
2. Run `bd list --status=in_progress --json --quiet` with a 2-second timeout
3. Parse each bead: extract `id`, `title`, `priority`
4. For each bead, check if the sideband file has phase info for that bead ID
5. Merge: sideband provides `phase`, bd provides `title` and `priority`
6. Format each bead as: `P{n} {id}: {title_truncated}... ({phase})`
7. Join multiple beads with `, `

**Priority colors (configurable via `colors.priority`):**
- P0: 196 (red)
- P1: 208 (orange)
- P2: 220 (yellow)
- P3: 75 (blue)
- P4: 245 (gray)

### 2. Refactor Layer 1.5 (sideband) into helper

Move current sideband reading into a function that returns bead_id + phase. The new bd query layer uses this for phase enrichment.

### 3. Update config schema

**File:** `scripts/install.sh`

Add `colors.priority` array to default config. Add `layers.bead_query` toggle (default true).

### 4. Update CLAUDE.md

Document the new layer and config options.

## Non-changes

- Layer 1 (dispatch), Layer 2 (phase), Layer 3 (clodex) — untouched
- Install flow — unchanged
- Rainbow clodex label — unchanged

## Testing

```bash
# Syntax check
bash -n scripts/statusline.sh

# Smoke test with sample input
echo '{"model":{"display_name":"Claude"},"workspace":{"project_dir":"/root/projects/Clavain","current_dir":"/root/projects/Clavain"},"session_id":"test"}' | bash scripts/statusline.sh
```
