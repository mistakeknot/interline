# Exploration: interline/scripts/statusline.sh Structure

## Summary

`statusline.sh` is a 403-line bash script that renders a workflow-aware statusline for Claude Code. It reads JSON state from stdin and outputs a colored, multi-layered status string. The file is organized into distinct logical sections covering configuration loading, helper functions, state layer processing, and final output assembly.

---

## 1. File Structure Overview

### Script Header & License (Lines 1-5)
- Line 1: `#!/bin/bash` shebang
- Lines 3-4: Comment documenting purpose and priority order (dispatch > bead context > phase > interserve > default)

### Main Sections
1. **Config Loading** (Lines 9-44)
2. **Helper Functions** (Lines 46-122)
3. **Input Extraction** (Lines 124-136)
4. **Priority Layers** (Lines 138-363)
5. **Status Line Assembly** (Lines 365-402)

---

## 2. Config Loading (Lines 9-44)

### Config File Path & Functions
```bash
_il_config="$HOME/.claude/interline.json"              # Line 11
_il_cfg() { ... }                                      # Lines 12-12: Single-value reader
_il_cfg_bool() { ... }                                 # Lines 13-18: Boolean coercion
```

### Pre-Read Config Values (Lines 21-33)
All configuration keys are read once at startup to avoid repeated jq calls:
- `cfg_sep` → separator (default: `" | "`)
- `cfg_branch_sep` → branch separator (default: `":"`)
- `cfg_interserve_label` → Clodex or custom
- `cfg_dispatch_prefix` → dispatch prefix label
- `cfg_color_*` → Color codes for all elements
- `cfg_title_max` → Max chars for truncation

### Default Values (Lines 35-44)
```bash
sep="${cfg_sep:- | }"                          # Line 36
branch_sep="${cfg_branch_sep:-:}"              # Line 37
interserve_label="${cfg_interserve_label:-Clodex}"  # Line 38
# ... more defaults
_il_interband_root="${INTERBAND_ROOT:-$HOME/.interband}"  # Line 44
_il_priority_defaults=(196 208 220 75 245)    # Line 43: P0-P4 colors
```

---

## 3. `_il_interband_root` Definition

**Location:** Line 44
```bash
_il_interband_root="${INTERBAND_ROOT:-$HOME/.interband}"
```

**Purpose:** Root directory for interband state files. Defaults to `$HOME/.interband` if `INTERBAND_ROOT` env var is not set.

**Used in:**
- Line 141: Dispatch state files glob
- Line 174: Coordination directory
- Line 245: Bead sideband file path
- Line 195: Signal file interband path

---

## 4. `_il_cfg_bool` Function

**Location:** Lines 13-18
```bash
_il_cfg_bool() {
  local v; v=$(_il_cfg "$1")
  # Default true: only disable if explicitly false
  [ "$v" = "false" ] && return 1
  return 0
}
```

**Purpose:** Coerces config values to booleans. Defaults to **true** (returns 0) unless explicitly set to the string `"false"`.

**Usage Pattern:**
- Checked for each layer: dispatch (line 140), coordination (line 171), bead (line 239), phase (line 323), interserve (line 359), bead_query (line 271), context (line 367)
- Example: `if _il_cfg_bool '.layers.dispatch'; then ...`

**Semantics:** 
- Returns 0 (true) if missing, empty, or any value except `"false"`
- Returns 1 (false) only if value is exactly `"false"`

---

## 5. `_il_interband_payload_field` Function

**Location:** Lines 78-86
```bash
_il_interband_payload_field() {
  local file="$1" jq_field="$2"
  jq -r \
    --arg field "$jq_field" \
    'if ((.version | tostring | startswith("1.")) and (.payload | type == "object"))
     then (.payload[$field] // empty)
     else empty
     end' "$file" 2>/dev/null
}
```

**Purpose:** Safely extracts a field from an interband envelope JSON file (v1.x schema).

**Parameters:**
- `$1` (file): Path to JSON file
- `$2` (jq_field): Field name to extract from `.payload` object

**Returns:** The field value, or nothing if:
- File doesn't exist
- Schema version is not 1.x (doesn't start with "1.")
- `.payload` is not an object
- Field doesn't exist in payload

**Usage Locations:**
- Line 148: Extract `name` from dispatch state file
- Line 149: Extract `activity` from dispatch state file
- Line 197: Extract `text` from coordination signal file
- Line 249: Extract `id` from bead sideband file
- Line 250: Extract `phase` from bead sideband file

---

## 6. Helper Functions (Lines 46-122)

### `_il_color()` (Lines 47-54)
Wraps text in ANSI 256-color escape codes. Takes color code (0-255) and text, outputs colored string.

### `_il_priority_color()` (Lines 57-65)
Returns the ANSI color code for a priority (P0-P4). Reads from config array `colors.priority[index]`, falls back to built-in defaults.

### `_il_truncate()` (Lines 68-75)
Truncates text to max length with ellipsis. Example: `"Hello World Long Text" → "Hello World Long..."`

### `_il_interserve_rainbow()` (Lines 89-122)
Renders interserve label with per-letter coloring (rainbow) or single color. Supports both array (per-letter) and scalar (uniform) config, with fallback to pastel defaults: `(210 216 228 157 111 183)`.

---

## 7. Input Extraction (Lines 124-136)

```bash
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')     # Line 125
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir')  # Line 126
project=$(basename "$project_dir")                                    # Line 127
transcript=$(echo "$input" | jq -r '.transcript_path // empty')      # Line 128
session_id=$(echo "$input" | jq -r '.session_id // empty')           # Line 129
context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')  # Line 130
```

### `session_id` 
**Lines:** 129
**Source:** Extracted from stdin JSON at key `.session_id`
**Used for:** Identifying session-specific sideband files (e.g., `~/.interband/interphase/bead/${session_id}.json`)
**Type:** String (UUIDv4 typically, but treated as opaque)

### Git Branch (Lines 133-136)
Extracted from `git symbolic-ref --short HEAD` or `git rev-parse --short HEAD` fallback. Stored in `$git_branch`.

---

## 8. Priority Layers

### Layer 1: Active Codex Dispatch (Lines 138-167)

**Condition:** `if _il_cfg_bool '.layers.dispatch'`

**State Files Scanned:**
- `/tmp/clavain-dispatch-*.json` (legacy)
- `$_il_interband_root/clavain/dispatch/*.json` (interband)

**Process:**
1. Extract PID from filename (`clavain-dispatch-<PID>.json`)
2. Check if process still alive (`kill -0 $pid`)
3. If alive, read `name` and `activity` fields
4. If activity is not "starting" or "done", show with activity in label
5. If stale (process died), delete the state file

**Output:** `dispatch_label` (colored with `cfg_color_dispatch`)

---

### Layer 1.25: Coordination Status (Lines 169-235)

**Condition:** `if [ -z "$dispatch_label" ] && _il_cfg_bool '.layers.coordination'`

**Requires:** `INTERMUTE_AGENT_ID` env var set

**State Sources:**
- Interband: `~/.interband/interlock/coordination/{project-slug}-{agent-id}.json`
- Legacy JSONL: `/var/run/intermute/signals/{project-slug}-{agent-id}.jsonl`

**Process:**
1. Count active agents from both interband and legacy sources
2. Read latest coordination signal from interband, fallback to JSONL
3. Build display showing agent count + signal text
4. Fallback to plain "coordination active" if no agents/signals

**Output:** `coord_label` (colored with `cfg_color_coordination`)

---

### Layer 1.5: Active Beads (Lines 237-319)

**Condition:** `if [ -z "$dispatch_label" ] && [ -z "$coord_label" ] && _il_cfg_bool '.layers.bead'`

**Sub-layers:**

**1.5a: Sideband File (Lines 241-267)**
- Reads session-specific bead metadata from `~/.interband/interphase/bead/${session_id}.json` (interband)
- Fallback: `/tmp/clavain-bead-${session_id}.json` (legacy)
- Extracts: bead `id`, `phase`
- File age check: Ignored if older than 24 hours

**1.5b: `bd` Query (Lines 269-273)**
- If `bead_query` layer enabled and `bd` command available
- Runs: `bd list --status=in_progress --json --quiet`
- Timeout: 2 seconds

**1.5c: Merge & Render (Lines 275-318)**
- If bd results exist: iterate through beads, extract id/title/priority
- Look up phase from sideband file (if matches bead id)
- Single bead: show full title (truncated); Multiple beads: ID only
- Format: `$(_il_color $priority_color "P${priority}") $(_il_color $cfg_color_bead "${id}: ${title}${phase}")`
- Fallback: Sideband-only display if bd unavailable

**Output:** `bead_label` (joined beads with commas)

---

### Layer 2: Workflow Phase (Lines 321-355)

**Condition:** `if [ -z "$dispatch_label" ] && [ -z "$coord_label" ] && _il_cfg_bool '.layers.phase'`

**Process:**
1. Scan transcript backwards (`tac`) for last Skill invocation (`"Skill"`)
2. Extract skill name from JSON
3. Strip namespace prefix (e.g., `clavain:brainstorm` → `brainstorm`)
4. Map skill name to human-readable phase name (Lines 334-348):
   - `brainstorm*` → "Brainstorming"
   - `strategy` → "Strategy"
   - `write-plan` → "Planning"
   - `flux-drive` → "Reviewing"
   - `work|execute-plan` → "Executing"
   - `quality-gates` → "Quality Gates"
   - `resolve` → "Resolving"
   - `landing-a-change` → "Shipping"
   - `interserve*` → "Dispatching"
   - `compound|engineering-docs` → "Documenting"
   - `interpeer|debate` → "Peer Review"
   - `smoke-test` → "Testing"
   - `doctor|heal-skill` → "Diagnostics"

**Output:** `phase_label` (colored with `cfg_color_phase`)

---

### Layer 3: Interserve Mode Flag (Lines 357-363)

**Condition:** `if _il_cfg_bool '.layers.interserve'`

**Process:** Checks for `$project_dir/.claude/clodex-toggle.flag` file. If present, appends ` with <rainbow-colored-label>` to status line.

**Output:** `interserve_suffix` (appended to model name in final line)

---

## 9. Context Window Display (Lines 365-377)

**Condition:** `if [ -n "$context_pct" ] && _il_cfg_bool '.layers.context'`

**Thresholds:**
- 95%+: Critical color (red, default 196)
- 80%-94%: Warning color (yellow, default 220)
- 0%-79%: Normal color (gray, default 245)

**Output:** ` · <pct>%` appended to model brackets

---

## 10. Build Status Line (Lines 379-400)

### Line 379: Marker Comment
```bash
# --- Build status line ---
```

### Base Template (Line 380)
```bash
status_line="[$model$interserve_suffix$context_display] $project"
```

Format: `[Claude with Clodex · 42%] interline`

### Branch Suffix (Lines 382-385)
If git branch exists, append: `${branch_sep}${git_display}`

Example: `[Claude] interline:main`

### Workflow Context (Lines 387-400)
Priority-based append logic:
1. If `dispatch_label` present: append with `$sep`
2. Else if `coord_label` present: append with `$sep`
3. Else: append `bead_label` + `phase_label` (if present) with `$sep`

---

## 11. Final Output (Line 402)

```bash
echo -e "$status_line"
```

**Note:** Uses `-e` flag to interpret backslash escapes (for ANSI color codes).

---

## 12. The `sep` Variable

**Location:** Line 36
```bash
sep="${cfg_sep:- | }"
```

**Purpose:** Main separator between status line segments (model → project → git → context → bead, etc.)

**Default:** `" | "` (space-pipe-space)

**Customization:** Via `~/.claude/interline.json` key `format.separator`

**Usage Locations:**
- Line 389: Between project and dispatch
- Line 391: Between project and coordination
- Line 395: Between project and bead
- Line 398: Between bead and phase

---

## 13. Key Data Flow Diagram

```
stdin JSON
    ↓
[Input Extraction: model, project_dir, session_id, context_pct, git_branch]
    ↓
[Layer 1: Dispatch → dispatch_label] (highest priority)
    ↓
[Layer 1.25: Coordination → coord_label] (if no dispatch)
    ↓
[Layer 1.5: Beads (sideband + bd) → bead_label] (if no dispatch/coord)
    ↓
[Layer 2: Phase → phase_label] (always checked)
    ↓
[Layer 3: Interserve flag → interserve_suffix] (always checked)
    ↓
[Context window → context_display] (always checked)
    ↓
[Assemble status_line with priority-based joins]
    ↓
echo -e "$status_line"
    ↓
stdout (colored terminal string)
```

---

## 14. Configuration Hierarchy

1. **~/.claude/interline.json** (user customization) — keys: `colors`, `layers`, `labels`, `format`
2. **Built-in defaults** (fallback):
   - Separators: ` | ` and `:`
   - Labels: `Clodex`
   - Colors: ANSI 256 codes
   - Layers: all enabled
   - Title max: 30 chars

---

## 15. Testing Entry Points

```bash
# Syntax check
bash -n scripts/statusline.sh

# Smoke test (create test JSON first)
echo '{"model": {"display_name": "Claude"}, "workspace": {"project_dir": "/tmp/test"}, "session_id": "abc123", "context_window": {"used_percentage": 42}}' | bash scripts/statusline.sh

# Expected output: [Claude · 42%] test
```

---

## Summary Table

| Element | Line(s) | Type | Purpose |
|---------|---------|------|---------|
| `_il_interband_root` | 44 | Variable | Root directory for interband state files |
| `_il_interband_payload_field()` | 78-86 | Function | Extract field from v1.x interband envelope |
| `_il_cfg_bool()` | 13-18 | Function | Coerce config to boolean (default true) |
| `session_id` | 129 | Variable | Session ID from stdin JSON |
| `sep` | 36 | Variable | Main separator (`" | "` default) |
| Build section | 379-400 | Code block | Assemble final status line |
| Final echo | 402 | Command | Output with ANSI escape interpretation |
| Layers 1-3 | 138-363 | Code blocks | Priority-ordered state rendering |
