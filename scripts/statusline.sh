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
cfg_color_context=$(_il_cfg '.colors.context')
cfg_color_context_warn=$(_il_cfg '.colors.context_warn')
cfg_color_context_critical=$(_il_cfg '.colors.context_critical')
cfg_color_delegation=$(_il_cfg '.colors.delegation')
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

# Helper: format seconds as compact age (e.g. 12s, 45m, 2h12m, 3d)
_il_fmt_age() {
  local s="$1"
  if [ "$s" -lt 60 ]; then
    echo "${s}s"
  elif [ "$s" -lt 3600 ]; then
    echo "$((s / 60))m"
  elif [ "$s" -lt 86400 ]; then
    echo "$((s / 3600))h$(( (s % 3600) / 60 ))m"
  else
    echo "$((s / 86400))d"
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
context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Detect this session's lane via the shared resolver (sideband → tmux name).
# Look for lib-lane.sh next to this script first (repo install), falling back
# to the canonical interline path (deployed-copy install at ~/.claude/).
# CLAUDE_SESSION_ID isn't always exported into the statusline runner, so pass
# the session_id we extracted from the JSON input through the env explicitly.
session_lane=""
_il_lane_lib=""
for _il_lane_candidate in \
  "$(dirname "${BASH_SOURCE[0]}")/lib-lane.sh" \
  "$HOME/projects/Sylveste/interverse/interline/scripts/lib-lane.sh"
do
  if [ -f "$_il_lane_candidate" ]; then
    _il_lane_lib="$_il_lane_candidate"
    break
  fi
done
if [ -n "$_il_lane_lib" ]; then
  source "$_il_lane_lib"
  _resolved=$(CLAUDE_SESSION_ID="${CLAUDE_SESSION_ID:-$session_id}" _il_lane_resolve 2>/dev/null)
  session_lane="${_resolved% *}"
fi
unset _il_lane_lib _il_lane_candidate _resolved

# Get git branch
git_branch=""
git_dirty=""
git_ahead=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  if [ -n "$git_branch" ] && _il_cfg_bool '.layers.dirty'; then
    dirty_count=$(git status --porcelain 2>/dev/null | wc -l)
    dirty_count=$(( dirty_count + 0 ))  # BSD wc pads with spaces; normalize
    if [ "${dirty_count:-0}" -gt 0 ]; then
      cfg_color_dirty=$(_il_cfg '.colors.dirty')
      git_dirty="$(_il_color "${cfg_color_dirty:-208}" "+${dirty_count}")"
    fi
  fi
  # Unpushed commits: committed-but-stranded work is invisible in the dirty
  # count. Prefer the upstream delta; for upstream-less branches fall back to
  # commits on no remote ref (mirrors auto-push.sh), guarded on origin
  # existing so remoteless scratch repos don't count their entire history.
  if [ -n "$git_branch" ] && _il_cfg_bool '.layers.ahead'; then
    ahead_count=$(git rev-list --count @{upstream}..HEAD 2>/dev/null)
    if [ -z "$ahead_count" ] && git remote get-url origin > /dev/null 2>&1; then
      ahead_count=$(git rev-list --count HEAD --not --remotes 2>/dev/null)
    fi
    if [ "${ahead_count:-0}" -gt 0 ]; then
      cfg_color_ahead=$(_il_cfg '.colors.ahead')
      git_ahead="$(_il_color "${cfg_color_ahead:-214}" "⇡${ahead_count}")"
    fi
  fi
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
  sideband_age=""
  if [ -n "$session_id" ]; then
    bead_file="$_il_interband_root/interphase/bead/${session_id}.json"
    if [ -f "$bead_file" ]; then
      file_age=$(( $(date +%s) - $(stat -c %Y "$bead_file" 2>/dev/null || echo 0) ))
      if [ "$file_age" -lt 86400 ]; then
        sideband_id=$(_il_interband_payload_field "$bead_file" "id")
        sideband_phase=$(_il_interband_payload_field "$bead_file" "phase")
        sideband_age="$file_age"
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
        sideband_age="$file_age"
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

      # Check if sideband has phase/age info for this bead
      b_phase=""
      if [ "$b_id" = "$sideband_id" ]; then
        _b_pieces=()
        [ -n "$sideband_phase" ] && _b_pieces+=("$sideband_phase")
        if [ -n "$sideband_age" ] && _il_cfg_bool '.layers.bead_age'; then
          _b_pieces+=("$(_il_fmt_age "$sideband_age")")
        fi
        if [ "${#_b_pieces[@]}" -gt 0 ]; then
          _b_joined=""
          for (( j=0; j<${#_b_pieces[@]}; j++ )); do
            [ $j -gt 0 ] && _b_joined="$_b_joined, "
            _b_joined="$_b_joined${_b_pieces[$j]}"
          done
          b_phase=" ($_b_joined)"
        fi
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
    # Fallback: sideband only (no bd available or bd_query disabled)
    local_bead="$sideband_id"
    _sb_pieces=()
    [ -n "$sideband_phase" ] && _sb_pieces+=("$sideband_phase")
    if [ -n "$sideband_age" ] && _il_cfg_bool '.layers.bead_age'; then
      _sb_pieces+=("$(_il_fmt_age "$sideband_age")")
    fi
    if [ "${#_sb_pieces[@]}" -gt 0 ]; then
      _sb_joined=""
      for (( j=0; j<${#_sb_pieces[@]}; j++ )); do
        [ $j -gt 0 ] && _sb_joined="$_sb_joined, "
        _sb_joined="$_sb_joined${_sb_pieces[$j]}"
      done
      local_bead="$local_bead ($_sb_joined)"
    fi
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

# --- Layer: Session ID (full, second line) ---
session_id_label=""
if _il_cfg_bool '.layers.session_id'; then
  if [ -n "$session_id" ]; then
    _il_sid_color=$(_il_cfg '.colors.session_id')
    session_id_label="$(_il_color "${_il_sid_color:-240}" "$session_id")"
  fi
fi

# --- Layer: Session stats (age + lines changed, from the stdin cost block) ---
# Answers "which pane is the long-running one and has it produced anything"
# without leaving the statusline. Dollar cost is opt-in (layers.cost: true) —
# on subscription plans the number is notional.
session_stats_label=""
if _il_cfg_bool '.layers.session_stats'; then
  IFS=$'\t' read -r _il_dur_ms _il_lines_add _il_lines_rem _il_cost_usd < <(
    echo "$input" | jq -r '[
      (.cost.total_duration_ms // 0),
      (.cost.total_lines_added // 0),
      (.cost.total_lines_removed // 0),
      (.cost.total_cost_usd // 0)
    ] | @tsv' 2>/dev/null)
  cfg_color_stats=$(_il_cfg '.colors.session_stats')
  _il_stats_parts=()
  _il_dur_s=$(( ${_il_dur_ms:-0} / 1000 ))
  # Under a minute is noise, not signal — a fresh session needs no age chip.
  if [ "$_il_dur_s" -ge 60 ]; then
    _il_stats_parts+=("$(_il_color "${cfg_color_stats:-245}" "$(_il_fmt_age "$_il_dur_s")")")
  fi
  if [ "$(( ${_il_lines_add:-0} + ${_il_lines_rem:-0} ))" -gt 0 ]; then
    cfg_color_lines_add=$(_il_cfg '.colors.lines_added')
    cfg_color_lines_rem=$(_il_cfg '.colors.lines_removed')
    _il_stats_parts+=("$(_il_color "${cfg_color_lines_add:-108}" "+${_il_lines_add}")$(_il_color "${cfg_color_lines_rem:-167}" "/-${_il_lines_rem}")")
  fi
  if [ "$(_il_cfg '.layers.cost')" = "true" ]; then
    _il_cost_fmt=$(printf '%.2f' "${_il_cost_usd:-0}" 2>/dev/null)
    if [ -n "$_il_cost_fmt" ] && [ "$_il_cost_fmt" != "0.00" ]; then
      _il_stats_parts+=("$(_il_color "${cfg_color_stats:-245}" "\$${_il_cost_fmt}")")
    fi
  fi
  if [ "${#_il_stats_parts[@]}" -gt 0 ]; then
    session_stats_label=""
    for (( i=0; i<${#_il_stats_parts[@]}; i++ )); do
      [ $i -gt 0 ] && session_stats_label="$session_stats_label · "
      session_stats_label="$session_stats_label${_il_stats_parts[$i]}"
    done
  fi
fi

# --- Layer 3: Branding label (toggle-gated or always-on) ---
interserve_suffix=""
if _il_cfg_bool '.layers.interserve'; then
  _il_always=$(_il_cfg '.layers.interserve_always')
  _il_show=false
  if [ "$_il_always" = "true" ]; then
    _il_show=true
  elif [ -f "$project_dir/.claude/clodex-toggle.flag" ]; then
    _il_show=true
  fi
  if [ "$_il_show" = "true" ]; then
    _il_version_label=""
    _il_version=$(_il_cfg '.labels.interserve_version')
    if [ -z "$_il_version" ]; then
      # Auto-detect from plugin cache if labels.interserve_version_auto is true
      if [ "$(_il_cfg '.labels.interserve_version_auto')" = "true" ]; then
        _il_pjson=$(ls -t ~/.claude/plugins/cache/*/clavain/*/.claude-plugin/plugin.json 2>/dev/null | head -1)
        if [ -n "$_il_pjson" ]; then
          _il_version=$(jq -r '.version // empty' "$_il_pjson" 2>/dev/null)
        fi
      fi
    fi
    if [ -n "$_il_version" ]; then
      _il_version_label=" v${_il_version}"
    fi
    interserve_suffix=" with $(_il_interserve_rainbow "$interserve_label")$(_il_color "${cfg_color_phase:-245}" "$_il_version_label")"
  fi
fi

# --- Build context window display (absolute tokens + % of window) ---
# Degradation evidence tracks ABSOLUTE token count, not window fraction —
# on a 1M model the 80% band (=800K) sits far past every measured quality
# knee. So severity is the worse of two scales: % of window (95/80, the
# out-of-space warning) and absolute used tokens (defaults 200k/100k,
# matching Anthropic's own 100K context-editing / 150K compaction
# defaults). Override via .thresholds.context_abs_warn_k / _critical_k.
context_display=""
if [ -n "$context_pct" ] && _il_cfg_bool '.layers.context'; then
  pct_int="${context_pct%.*}"  # strip decimal
  ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
  ctx_used=$(echo "$input" | jq -r '.context_window.current_usage
    | if . == null then 0
      else ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
      end' 2>/dev/null)
  ctx_used="${ctx_used:-0}"
  # current_usage is null right after /compact — derive from the % instead
  if [ "${ctx_used:-0}" -eq 0 ] && [ "${ctx_size:-0}" -gt 0 ] && [ "${pct_int:-0}" -gt 0 ]; then
    ctx_used=$(( ctx_size * pct_int / 100 ))
  fi
  ctx_used_k=$(( ctx_used / 1000 ))

  ctx_abs_warn_k=$(_il_cfg '.thresholds.context_abs_warn_k')
  ctx_abs_warn_k="${ctx_abs_warn_k:-100}"
  ctx_abs_crit_k=$(_il_cfg '.thresholds.context_abs_critical_k')
  ctx_abs_crit_k="${ctx_abs_crit_k:-200}"

  ctx_sev=0
  [ "${pct_int:-0}" -ge 80 ] && ctx_sev=1
  [ "$ctx_used_k" -ge "$ctx_abs_warn_k" ] && ctx_sev=1
  [ "${pct_int:-0}" -ge 95 ] && ctx_sev=2
  [ "$ctx_used_k" -ge "$ctx_abs_crit_k" ] && ctx_sev=2
  case "$ctx_sev" in
    2) ctx_color="${cfg_color_context_critical:-196}" ;;
    1) ctx_color="${cfg_color_context_warn:-220}" ;;
    *) ctx_color="${cfg_color_context:-245}" ;;
  esac

  ctx_label="${pct_int}%"
  [ "$ctx_used_k" -gt 0 ] && ctx_label="${ctx_used_k}k·${pct_int}%"
  context_display=" · $(_il_color "$ctx_color" "$ctx_label")"
fi

# --- Layer 4: Context pressure from intercheck interband signal ---
pressure_label=""
if _il_cfg_bool '.layers.pressure'; then
  if [ -n "$session_id" ]; then
    _il_pressure_file="$_il_interband_root/intercheck/pressure/${session_id}.json"
    if [ -f "$_il_pressure_file" ]; then
      _il_pressure_level=$(_il_interband_payload_field "$_il_pressure_file" "level")
      if [ -n "$_il_pressure_level" ] && [ "$_il_pressure_level" != "green" ]; then
        case "$_il_pressure_level" in
          yellow)  _il_pressure_color="${cfg_color_context_warn:-220}" ;;
          orange)  _il_pressure_color="208" ;;
          red)     _il_pressure_color="${cfg_color_context_critical:-196}" ;;
          *)       _il_pressure_color="245" ;;
        esac
        pressure_label="$(_il_color "$_il_pressure_color" "$_il_pressure_level")"
      fi
    fi
  fi
fi

# --- Layer 5: Budget alert from interstat interband signal ---
budget_label=""
if _il_cfg_bool '.layers.budget'; then
  if [ -n "$session_id" ]; then
    _il_budget_file="$_il_interband_root/interstat/budget/${session_id}.json"
    if [ -f "$_il_budget_file" ]; then
      _il_budget_pct=$(_il_interband_payload_field "$_il_budget_file" "pct_consumed")
      if [ -n "$_il_budget_pct" ]; then
        _il_budget_int="${_il_budget_pct%.*}"
        # Guard against non-numeric values (e.g., jq returning "null")
        case "$_il_budget_int" in ''|*[!0-9]*) _il_budget_int=0 ;; esac
        if [ "${_il_budget_int:-0}" -ge 80 ]; then
          _il_budget_color="${cfg_color_context_critical:-196}"
          budget_label="$(_il_color "$_il_budget_color" "${_il_budget_int}% budget")"
        elif [ "${_il_budget_int:-0}" -ge 50 ]; then
          _il_budget_color="${cfg_color_context_warn:-220}"
          budget_label="$(_il_color "$_il_budget_color" "${_il_budget_int}% budget")"
        fi
      fi
    fi
  fi
fi

# --- Layer: Loop-breaker gate alert (Clavain stop-hook suppression state) ---
# The stop-hook loop breaker goes deliberately silent after its one BLOCKED
# message (lib-loop-breaker.sh) — this marker is the only surface telling the
# user the session is parked on a human gate. State file read is cheap; the
# telemetry grep for the fire count only runs once a session is actually
# suppressed, so the common case costs one [ -f ] test.
loop_label=""
if _il_cfg_bool '.layers.loop_breaker' && [ -n "$session_id" ]; then
  _il_lb_dir="${CLAVAIN_LOOP_BREAKER_DIR:-$HOME/.clavain/stop-loop-breaker}"
  _il_lb_file="$_il_lb_dir/$(echo "$session_id" | tr '/:' '__').json"
  if [ -f "$_il_lb_file" ]; then
    _il_lb_suppressed=$(jq -r '.suppressed // false' "$_il_lb_file" 2>/dev/null)
    if [ "$_il_lb_suppressed" = "true" ]; then
      _il_lb_count=""
      _il_lb_telemetry="$HOME/.clavain/telemetry.jsonl"
      if [ -f "$_il_lb_telemetry" ]; then
        _il_lb_n=$(grep '"stop_loop_suppression"' "$_il_lb_telemetry" 2>/dev/null \
          | grep -c -- "$session_id" 2>/dev/null)
        [ "${_il_lb_n:-0}" -gt 0 ] && _il_lb_count="×${_il_lb_n}"
      fi
      cfg_color_loop=$(_il_cfg '.colors.loop_breaker')
      loop_label="$(_il_color "${cfg_color_loop:-196}" "gate⛔${_il_lb_count}")"
    fi
  fi
fi

# --- Layer: Next ready bead (top of `bd ready`, scoped to session lane) ---
# Renders only when a session lane is detected — avoids showing the same global
# top-of-ready in every tmux pane. Lane comes from the sideband file if set,
# otherwise from the tmux session name (see lane detection above).
next_bead_label=""
if _il_cfg_bool '.layers.next_bead' && [ -n "$session_lane" ] && command -v bd > /dev/null 2>&1; then
  next_json=$(timeout 2 bd ready --label="$session_lane" --json --limit 1 --quiet 2>/dev/null || true)
  if [ -n "$next_json" ] && [ "$next_json" != "null" ] && [ "$next_json" != "[]" ]; then
    n_id=$(echo "$next_json" | jq -r '.[0].id // empty' 2>/dev/null)
    n_priority=$(echo "$next_json" | jq -r '.[0].priority // 4' 2>/dev/null)
    if [ -n "$n_id" ]; then
      cfg_color_next_bead=$(_il_cfg '.colors.next_bead')
      np_color=$(_il_priority_color "$n_priority")
      next_bead_label="→ $(_il_color "$np_color" "P${n_priority}") $(_il_color "${cfg_color_next_bead:-${cfg_color_bead}}" "$n_id")"
    fi
  fi
fi

# --- Layer 6: Delegation stats from interspect DB ---
delegation_label=""
if _il_cfg_bool '.layers.delegation'; then
  if [ -n "$session_id" ] && [ -n "$project_dir" ]; then
    _il_deleg_db="${project_dir}/.clavain/interspect/interspect.db"
    if [ -f "$_il_deleg_db" ] && command -v sqlite3 > /dev/null 2>&1; then
      _il_deleg_row=$(sqlite3 "$_il_deleg_db" \
        "SELECT COUNT(*), SUM(CASE WHEN json_extract(context,'\$.verdict') IN ('pass','CLEAN') THEN 1 ELSE 0 END) FROM evidence WHERE event='delegation_outcome' AND source='codex-delegate' AND session_id='${session_id}';" 2>/dev/null)
      if [ -n "$_il_deleg_row" ]; then
        _il_deleg_total="${_il_deleg_row%%|*}"
        _il_deleg_pass="${_il_deleg_row##*|}"
        : "${_il_deleg_total:=0}" "${_il_deleg_pass:=0}"
        if [ "${_il_deleg_total:-0}" -gt 0 ]; then
          _il_deleg_pct=$(( _il_deleg_pass * 100 / _il_deleg_total ))
          delegation_label="$(_il_color "${cfg_color_delegation:-157}" "Dx: ${_il_deleg_pass}/${_il_deleg_total} (${_il_deleg_pct}%)")"
        fi
      fi
    fi
  fi
fi

# --- Build status line ---
status_line="[$model$interserve_suffix$context_display] $project"

if [ -n "$git_branch" ]; then
  git_display="$(_il_color "$cfg_color_branch" "$git_branch")"
  [ -n "$git_dirty" ] && git_display="${git_display}${git_dirty}"
  [ -n "$git_ahead" ] && git_display="${git_display}${git_ahead}"
  status_line="$status_line${branch_sep}${git_display}"
fi

# Append workflow context (dispatch > coordination > bead + phase)
if [ -n "$dispatch_label" ]; then
  status_line="$status_line${sep}$dispatch_label"
elif [ -n "$coord_label" ]; then
  status_line="$status_line${sep}$coord_label"
else
  if [ -n "$phase_label" ]; then
    status_line="$status_line${sep}$phase_label"
  fi
fi

# Append ambient indicators (always visible, independent of dispatch/coord/bead)
if [ -n "$loop_label" ]; then
  status_line="$status_line${sep}$loop_label"
fi
if [ -n "$pressure_label" ]; then
  status_line="$status_line${sep}$pressure_label"
fi
if [ -n "$budget_label" ]; then
  status_line="$status_line${sep}$budget_label"
fi
if [ -n "$delegation_label" ]; then
  status_line="$status_line${sep}$delegation_label"
fi

# Second line: session ID + stats + bead + next-bead
second_line=""
if [ -n "$session_id_label" ]; then
  second_line="$session_id_label"
fi
if [ -n "$session_stats_label" ]; then
  [ -n "$second_line" ] && second_line="$second_line${sep}$session_stats_label" || second_line="$session_stats_label"
fi
if [ -n "$bead_label" ]; then
  [ -n "$second_line" ] && second_line="$second_line${sep}$bead_label" || second_line="$bead_label"
fi
if [ -n "$next_bead_label" ]; then
  [ -n "$second_line" ] && second_line="$second_line${sep}$next_bead_label" || second_line="$next_bead_label"
fi
if [ -n "$second_line" ]; then
  status_line="$status_line\n$second_line"
fi

echo -e "$status_line"
