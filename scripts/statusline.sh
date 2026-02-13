#!/bin/bash

# Claude Code statusline — workflow-aware with dispatch state tracking
# Priority: dispatch state > transcript phase > clodex mode > default

# Read JSON input from stdin
input=$(cat)

# --- Config loading ---
# All fields optional; missing file or keys = built-in defaults
_il_config="$HOME/.claude/interline.json"
_il_cfg() { [ -f "$_il_config" ] && jq -r "$1" "$_il_config" 2>/dev/null | grep -v '^null$'; }
_il_cfg_bool() {
  local v; v=$(_il_cfg "$1")
  # Default true: only disable if explicitly false
  [ "$v" = "false" ] && return 1
  return 0
}

# Pre-read config values (avoid repeated jq calls)
cfg_sep=$(_il_cfg '.format.separator')
cfg_branch_sep=$(_il_cfg '.format.branch_separator')
cfg_clodex_label=$(_il_cfg '.labels.clodex')
cfg_dispatch_prefix=$(_il_cfg '.labels.dispatch_prefix')
cfg_color_dispatch=$(_il_cfg '.colors.dispatch')
cfg_color_bead=$(_il_cfg '.colors.bead')
cfg_color_phase=$(_il_cfg '.colors.phase')
cfg_color_branch=$(_il_cfg '.colors.branch')

# Apply defaults
sep="${cfg_sep:- | }"
branch_sep="${cfg_branch_sep:-:}"
clodex_label="${cfg_clodex_label:-Clodex}"
dispatch_prefix="${cfg_dispatch_prefix:-Clodex}"

# Helper: wrap text in ANSI 256-color
_il_color() {
  local code="$1" text="$2"
  if [ -n "$code" ]; then
    echo -n "\033[38;5;${code}m${text}\033[0m"
  else
    echo -n "$text"
  fi
}

# Helper: render clodex label with rainbow or single color
_il_clodex_rainbow() {
  local label="$1"
  if [ -f "$_il_config" ]; then
    # Check if colors.clodex is an array
    local arr_len
    arr_len=$(jq '.colors.clodex | if type == "array" then length else 0 end' "$_il_config" 2>/dev/null)
    if [ "${arr_len:-0}" -gt 0 ]; then
      # Per-letter coloring from array
      local result="" i=0 c len=${#label}
      while [ "$i" -lt "$len" ]; do
        c=$(jq -r ".colors.clodex[$((i % arr_len))]" "$_il_config" 2>/dev/null)
        result="${result}\033[38;5;${c}m${label:$i:1}"
        i=$((i + 1))
      done
      echo -n "${result}\033[0m"
      return
    fi
    # Check if colors.clodex is a scalar
    local scalar
    scalar=$(jq -r '.colors.clodex | if type == "number" then tostring else empty end' "$_il_config" 2>/dev/null)
    if [ -n "$scalar" ]; then
      echo -n "\033[38;5;${scalar}m${label}\033[0m"
      return
    fi
  fi
  # Default pastel rainbow: 210 216 228 157 111 183
  local defaults=(210 216 228 157 111 183)
  local result="" i=0 len=${#label}
  while [ "$i" -lt "$len" ]; do
    result="${result}\033[38;5;${defaults[$((i % ${#defaults[@]}))]}m${label:$i:1}"
    i=$((i + 1))
  done
  echo -n "${result}\033[0m"
}

# Extract values using jq
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir')
project=$(basename "$project_dir")
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# Get git branch
git_branch=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
fi

# --- Layer 1: Check for active Codex dispatch ---
dispatch_label=""
if _il_cfg_bool '.layers.dispatch'; then
  for state_file in /tmp/clavain-dispatch-*.json; do
    [ -f "$state_file" ] || continue
    # Verify the owning process is still alive
    pid="${state_file##*-}"
    pid="${pid%.json}"
    if kill -0 "$pid" 2>/dev/null; then
      name=$(jq -r '.name // "codex"' "$state_file" 2>/dev/null)
      dispatch_label="$(_il_color "$cfg_color_dispatch" "${dispatch_prefix}: ${name}")"
      break
    else
      # Stale state file — owning process died without cleanup
      rm -f "$state_file"
    fi
  done
fi

# --- Layer 1.5: Check for active bead context ---
bead_label=""
if [ -z "$dispatch_label" ] && _il_cfg_bool '.layers.bead'; then
  session_id=$(echo "$input" | jq -r '.session_id // empty')
  if [ -n "$session_id" ]; then
    bead_file="/tmp/clavain-bead-${session_id}.json"
    if [ -f "$bead_file" ]; then
      # Skip stale files (>24h old)
      file_age=$(( $(date +%s) - $(stat -c %Y "$bead_file" 2>/dev/null || echo 0) ))
      if [ "$file_age" -lt 86400 ]; then
        bead_id=$(jq -r '.id // empty' "$bead_file" 2>/dev/null)
        bead_phase=$(jq -r '.phase // empty' "$bead_file" 2>/dev/null)
        if [ -n "$bead_id" ]; then
          local_bead="$bead_id"
          [ -n "$bead_phase" ] && local_bead="$local_bead ($bead_phase)"
          bead_label="$(_il_color "$cfg_color_bead" "$local_bead")"
        fi
      fi
    fi
  fi
fi

# --- Layer 2: Scan transcript for last workflow phase ---
phase_label=""
if [ -z "$dispatch_label" ] && _il_cfg_bool '.layers.phase'; then
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    # Find last Skill invocation — scan backwards, stop at first match
    skill_line=$(tac "$transcript" 2>/dev/null | grep -m1 '"Skill"' || true)
    if [ -n "$skill_line" ]; then
      # Extract skill name from the tool_use input
      skill_name=$(echo "$skill_line" | grep -oP '"skill"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"skill"\s*:\s*"//;s/".*//')
      if [ -n "$skill_name" ]; then
        # Strip namespace prefix (e.g., "clavain:brainstorm" -> "brainstorm")
        skill_short="${skill_name##*:}"
        phase_text=""
        case "$skill_short" in
          brainstorm*)        phase_text="Brainstorming" ;;
          strategy)           phase_text="Strategy" ;;
          write-plan)         phase_text="Planning" ;;
          flux-drive)         phase_text="Reviewing" ;;
          work|execute-plan)  phase_text="Executing" ;;
          quality-gates)      phase_text="Quality Gates" ;;
          resolve)            phase_text="Resolving" ;;
          landing-a-change)   phase_text="Shipping" ;;
          clodex*)            phase_text="Dispatching" ;;
          compound|engineering-docs) phase_text="Documenting" ;;
          interpeer|debate)   phase_text="Peer Review" ;;
          smoke-test)         phase_text="Testing" ;;
          doctor|heal-skill)  phase_text="Diagnostics" ;;
        esac
        if [ -n "$phase_text" ]; then
          phase_label="$(_il_color "$cfg_color_phase" "$phase_text")"
        fi
      fi
    fi
  fi
fi

# --- Layer 3: Check for clodex mode flag (always visible when active) ---
clodex_suffix=""
if _il_cfg_bool '.layers.clodex'; then
  if [ -f "$project_dir/.claude/clodex-toggle.flag" ]; then
    clodex_suffix=" with $(_il_clodex_rainbow "$clodex_label")"
  fi
fi

# --- Build status line ---
status_line="[$model$clodex_suffix] $project"

if [ -n "$git_branch" ]; then
  git_display="$(_il_color "$cfg_color_branch" "$git_branch")"
  status_line="$status_line${branch_sep}${git_display}"
fi

# Append workflow context (dispatch > bead + phase)
if [ -n "$dispatch_label" ]; then
  status_line="$status_line${sep}$dispatch_label"
else
  # Bead and phase are shown together: "Clavain-021h (planned) | Executing"
  if [ -n "$bead_label" ]; then
    status_line="$status_line${sep}$bead_label"
  fi
  if [ -n "$phase_label" ]; then
    status_line="$status_line${sep}$phase_label"
  fi
fi

echo -e "$status_line"
