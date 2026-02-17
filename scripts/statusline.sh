#!/bin/bash

# Claude Code statusline — workflow-aware with dispatch state tracking
# Priority: dispatch state > bead context > transcript phase > interserve mode > default

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
cfg_interserve_label=$(_il_cfg '.labels.interserve')
cfg_dispatch_prefix=$(_il_cfg '.labels.dispatch_prefix')
cfg_color_dispatch=$(_il_cfg '.colors.dispatch')
cfg_color_bead=$(_il_cfg '.colors.bead')
cfg_color_phase=$(_il_cfg '.colors.phase')
cfg_color_branch=$(_il_cfg '.colors.branch')
cfg_color_coordination=$(_il_cfg '.colors.coordination')
cfg_title_max=$(_il_cfg '.format.title_max_chars')

# Apply defaults
sep="${cfg_sep:- | }"
branch_sep="${cfg_branch_sep:-:}"
interserve_label="${cfg_interserve_label:-Clodex}"
dispatch_prefix="${cfg_dispatch_prefix:-Clodex}"
title_max="${cfg_title_max:-30}"

# Default priority colors: P0=red, P1=orange, P2=yellow, P3=blue, P4=gray
_il_priority_defaults=(196 208 220 75 245)
_il_interband_root="${INTERBAND_ROOT:-$HOME/.interband}"

# Helper: wrap text in ANSI 256-color
_il_color() {
  local code="$1" text="$2"
  if [ -n "$code" ]; then
    echo -n "\033[38;5;${code}m${text}\033[0m"
  else
    echo -n "$text"
  fi
}

# Helper: get priority color (from config or defaults)
_il_priority_color() {
  local p="$1"
  if [ -f "$_il_config" ]; then
    local c
    c=$(jq -r ".colors.priority[$p] // empty" "$_il_config" 2>/dev/null)
    [ -n "$c" ] && echo "$c" && return
  fi
  echo "${_il_priority_defaults[$p]:-245}"
}

# Helper: truncate text with ellipsis
_il_truncate() {
  local text="$1" max="$2"
  if [ "${#text}" -gt "$max" ]; then
    echo "${text:0:$((max - 3))}..."
  else
    echo "$text"
  fi
}

# Helper: read field from interband envelope payload.
_il_interband_payload_field() {
  local file="$1" jq_field="$2"
  jq -r \
    --arg field "$jq_field" \
    'if ((.version | tostring | startswith("1.")) and (.payload | type == "object"))
     then (.payload[$field] // empty)
     else empty
     end' "$file" 2>/dev/null
}

# Helper: render interserve label with rainbow or single color
_il_interserve_rainbow() {
  local label="$1"
  if [ -f "$_il_config" ]; then
    # Check if colors.interserve is an array
    local arr_len
    arr_len=$(jq '.colors.interserve | if type == "array" then length else 0 end' "$_il_config" 2>/dev/null)
    if [ "${arr_len:-0}" -gt 0 ]; then
      # Per-letter coloring from array
      local result="" i=0 c len=${#label}
      while [ "$i" -lt "$len" ]; do
        c=$(jq -r ".colors.interserve[$((i % arr_len))]" "$_il_config" 2>/dev/null)
        result="${result}\033[38;5;${c}m${label:$i:1}"
        i=$((i + 1))
      done
      echo -n "${result}\033[0m"
      return
    fi
    # Check if colors.interserve is a scalar
    local scalar
    scalar=$(jq -r '.colors.interserve | if type == "number" then tostring else empty end' "$_il_config" 2>/dev/null)
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
session_id=$(echo "$input" | jq -r '.session_id // empty')

# Get git branch
git_branch=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
fi

# --- Layer 1: Check for active Codex dispatch ---
dispatch_label=""
if _il_cfg_bool '.layers.dispatch'; then
  for state_file in /tmp/clavain-dispatch-*.json "$_il_interband_root"/clavain/dispatch/*.json; do
    [ -f "$state_file" ] || continue
    # Verify the owning process is still alive
    pid="${state_file##*/}"
    pid="${pid%.json}"
    pid="${pid##*-}"
    if kill -0 "$pid" 2>/dev/null; then
      name=$(_il_interband_payload_field "$state_file" "name")
      activity=$(_il_interband_payload_field "$state_file" "activity")
      if [ -z "$name" ]; then
        name=$(jq -r '.name // "codex"' "$state_file" 2>/dev/null)
      fi
      if [ -z "$activity" ]; then
        activity=$(jq -r '.activity // empty' "$state_file" 2>/dev/null)
      fi
      if [ -n "$activity" ] && [ "$activity" != "starting" ] && [ "$activity" != "done" ]; then
        dispatch_label="$(_il_color "$cfg_color_dispatch" "${dispatch_prefix}: ${name} (${activity})")"
      else
        dispatch_label="$(_il_color "$cfg_color_dispatch" "${dispatch_prefix}: ${name}")"
      fi
      break
    else
      # Stale state file — owning process died without cleanup
      rm -f "$state_file"
    fi
  done
fi

# --- Layer 1.25: Coordination status (interlock signal files) ---
coord_label=""
if [ -z "$dispatch_label" ] && _il_cfg_bool '.layers.coordination'; then
  if [ -n "${INTERMUTE_AGENT_ID:-}" ]; then
    _il_signal_dir="/var/run/intermute/signals"
    _il_coord_dir="$_il_interband_root/interlock/coordination"
    _il_project_slug="$project"

    # Count active agents from both interband snapshots and legacy JSONL streams.
    _il_agent_count=0
    _il_agent_count_interband=0
    _il_agent_count_legacy=0
    if [ -d "$_il_coord_dir" ]; then
      _il_agent_count_interband=$(ls -1 "${_il_coord_dir}/${_il_project_slug}"-*.json 2>/dev/null | wc -l)
    fi
    if [ -d "$_il_signal_dir" ]; then
      _il_agent_count_legacy=$(ls -1 "${_il_signal_dir}/${_il_project_slug}"-*.jsonl 2>/dev/null | wc -l)
    fi
    if [ "${_il_agent_count_interband:-0}" -gt "${_il_agent_count_legacy:-0}" ]; then
      _il_agent_count="$_il_agent_count_interband"
    else
      _il_agent_count="$_il_agent_count_legacy"
    fi

    # Read this agent's latest signal snapshot from interband first.
    _il_signal_text=""
    _il_signal_file_interband="${_il_coord_dir}/${_il_project_slug}-${INTERMUTE_AGENT_ID}.json"
    if [ -f "$_il_signal_file_interband" ]; then
      _il_signal_text=$(_il_interband_payload_field "$_il_signal_file_interband" "text")
    fi

    # Backward-compatible fallback: read legacy JSONL signal stream.
    if [ -z "$_il_signal_text" ]; then
      _il_signal_file="${_il_signal_dir}/${_il_project_slug}-${INTERMUTE_AGENT_ID}.jsonl"
      if [ -f "$_il_signal_file" ]; then
        _il_latest=$(tail -1 "$_il_signal_file" 2>/dev/null)
        if [ -n "$_il_latest" ]; then
          _il_sig_version=$(echo "$_il_latest" | jq -r '.version // 0' 2>/dev/null)
          if [ "$_il_sig_version" = "1" ]; then
            _il_signal_text=$(echo "$_il_latest" | jq -r '.text // empty' 2>/dev/null)
          else
            echo "interline: unknown signal schema version $_il_sig_version, skipping" >&2
          fi
        fi
      fi
    fi

    # Build coordination display
    if [ "$_il_agent_count" -gt 0 ] || [ -n "$_il_signal_text" ]; then
      _il_coord_display=""
      if [ "$_il_agent_count" -gt 0 ]; then
        _il_coord_display="${_il_agent_count} agents"
      fi
      if [ -n "$_il_signal_text" ]; then
        _il_signal_short=$(_il_truncate "$_il_signal_text" "$title_max")
        if [ -n "$_il_coord_display" ]; then
          _il_coord_display="${_il_coord_display} | ${_il_signal_short}"
        else
          _il_coord_display="$_il_signal_short"
        fi
      fi
      coord_label="$(_il_color "$cfg_color_coordination" "$_il_coord_display")"
    else
      coord_label="$(_il_color "$cfg_color_coordination" "coordination active")"
    fi
  fi
fi

# --- Layer 1.5: Active beads (sideband + bd query) ---
bead_label=""
if [ -z "$dispatch_label" ] && [ -z "$coord_label" ] && _il_cfg_bool '.layers.bead'; then

  # --- 1.5a: Read sideband file for phase context ---
  sideband_id=""
  sideband_phase=""
  if [ -n "$session_id" ]; then
    bead_file="$_il_interband_root/interphase/bead/${session_id}.json"
    if [ -f "$bead_file" ]; then
      file_age=$(( $(date +%s) - $(stat -c %Y "$bead_file" 2>/dev/null || echo 0) ))
      if [ "$file_age" -lt 86400 ]; then
        sideband_id=$(_il_interband_payload_field "$bead_file" "id")
        sideband_phase=$(_il_interband_payload_field "$bead_file" "phase")
      fi
    fi

    # Backward-compatible fallback to legacy sideband path.
    if [ -z "$sideband_id" ] || [ -z "$sideband_phase" ]; then
      bead_file="/tmp/clavain-bead-${session_id}.json"
    else
      bead_file=""
    fi
    if [ -n "$bead_file" ] && [ -f "$bead_file" ]; then
      file_age=$(( $(date +%s) - $(stat -c %Y "$bead_file" 2>/dev/null || echo 0) ))
      if [ "$file_age" -lt 86400 ]; then
        sideband_id=$(jq -r '.id // empty' "$bead_file" 2>/dev/null)
        sideband_phase=$(jq -r '.phase // empty' "$bead_file" 2>/dev/null)
      fi
    fi
  fi

  # --- 1.5b: Query bd for all in_progress beads ---
  bd_beads=""
  if _il_cfg_bool '.layers.bead_query' && command -v bd > /dev/null 2>&1; then
    bd_beads=$(timeout 2 bd list --status=in_progress --json --quiet 2>/dev/null || true)
  fi

  # --- 1.5c: Merge sideband + bd into bead display ---
  bead_parts=()

  if [ -n "$bd_beads" ] && [ "$bd_beads" != "null" ] && [ "$bd_beads" != "[]" ]; then
    # Parse bd results and format each bead
    bead_count=$(echo "$bd_beads" | jq 'length' 2>/dev/null)
    for (( i=0; i<${bead_count:-0}; i++ )); do
      b_id=$(echo "$bd_beads" | jq -r ".[$i].id // empty" 2>/dev/null)
      b_title=$(echo "$bd_beads" | jq -r ".[$i].title // empty" 2>/dev/null)
      b_priority=$(echo "$bd_beads" | jq -r ".[$i].priority // 4" 2>/dev/null)
      [ -z "$b_id" ] && continue

      # Check if sideband has phase info for this bead
      b_phase=""
      if [ "$b_id" = "$sideband_id" ] && [ -n "$sideband_phase" ]; then
        b_phase=" ($sideband_phase)"
      fi

      p_color=$(_il_priority_color "$b_priority")
      if [ "${bead_count:-0}" -eq 1 ]; then
        # Single bead: full format with title
        b_title_short=$(_il_truncate "$b_title" "$title_max")
        bead_entry="$(_il_color "$p_color" "P${b_priority}") $(_il_color "$cfg_color_bead" "${b_id}: ${b_title_short}${b_phase}")"
      else
        # Multiple beads: ID only to save space
        bead_entry="$(_il_color "$p_color" "P${b_priority}") $(_il_color "$cfg_color_bead" "${b_id}${b_phase}")"
      fi
      bead_parts+=("$bead_entry")
    done
  elif [ -n "$sideband_id" ]; then
    # Fallback: sideband only (no bd available)
    local_bead="$sideband_id"
    [ -n "$sideband_phase" ] && local_bead="$local_bead ($sideband_phase)"
    bead_parts+=("$(_il_color "$cfg_color_bead" "$local_bead")")
  fi

  # Join bead parts with comma
  if [ ${#bead_parts[@]} -gt 0 ]; then
    bead_label=""
    for (( i=0; i<${#bead_parts[@]}; i++ )); do
      [ $i -gt 0 ] && bead_label="$bead_label, "
      bead_label="$bead_label${bead_parts[$i]}"
    done
  fi
fi

# --- Layer 2: Scan transcript for last workflow phase ---
phase_label=""
if [ -z "$dispatch_label" ] && [ -z "$coord_label" ] && _il_cfg_bool '.layers.phase'; then
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
          interserve*)        phase_text="Dispatching" ;;
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

# --- Layer 3: Check for interserve mode flag (always visible when active) ---
interserve_suffix=""
if _il_cfg_bool '.layers.interserve'; then
  if [ -f "$project_dir/.claude/clodex-toggle.flag" ]; then
    interserve_suffix=" with $(_il_interserve_rainbow "$interserve_label")"
  fi
fi

# --- Build status line ---
status_line="[$model$interserve_suffix] $project"

if [ -n "$git_branch" ]; then
  git_display="$(_il_color "$cfg_color_branch" "$git_branch")"
  status_line="$status_line${branch_sep}${git_display}"
fi

# Append workflow context (dispatch > coordination > bead + phase)
if [ -n "$dispatch_label" ]; then
  status_line="$status_line${sep}$dispatch_label"
elif [ -n "$coord_label" ]; then
  status_line="$status_line${sep}$coord_label"
else
  # Bead and phase are shown together: "P1 Clavain-4jeg: title... (executing) | Reviewing"
  if [ -n "$bead_label" ]; then
    status_line="$status_line${sep}$bead_label"
  fi
  if [ -n "$phase_label" ]; then
    status_line="$status_line${sep}$phase_label"
  fi
fi

echo -e "$status_line"
