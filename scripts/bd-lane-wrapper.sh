#!/usr/bin/env bash
# bd-lane-wrapper.sh — auto-tag `bd create` with the session's lane.
#
# Source from your shell init:
#   [ -f /path/to/interline/scripts/bd-lane-wrapper.sh ] && \
#     source /path/to/interline/scripts/bd-lane-wrapper.sh
#
# Resolves a lane in this order, stops at first hit:
#   1. Sideband file: $HOME/.interband/interphase/lane/${CLAUDE_SESSION_ID}.json
#   2. Tmux session name parse (same rules as interline statusline)
#   3. Haiku 4.5 classification of title (only when title is present)
#
# Skips injection when:
#   - User passes --labels / -l (respects explicit intent)
#   - User passes --no-lane (escape hatch; flag is stripped before forwarding)
#   - No lane resolved from any source
#
# Env knobs:
#   BD_LANE_DEBUG=1      Print "auto-tag: lane=X (source)" to stderr
#   BD_LANE_VOCAB="..."  Override Haiku candidate list (comma-separated)
#   BD_LANE_DISABLE=1    Bypass entirely; forward to real bd

_il_bd_real() { command bd "$@"; }

_il_bd_log() { [ "${BD_LANE_DEBUG:-0}" = "1" ] && echo "bd-lane: $*" >&2 || true; }

# Extract a lane from a tmux-style session name.
# Recognized: ...[[[<lane>@..., ...]]]<lane>|..., ...[[[<lane>$ (no terminator).
# The trailing terminator is optional, so sessions named without an `@<model>`
# suffix (e.g. `[warp[[sylveste[[[feedback`) still resolve.
# Bare alphanumeric session names are also returned as-is.
_il_bd_parse_session_name() {
  local sn="$1"
  [ -z "$sn" ] && return 1
  local cand
  cand=$(echo "$sn" | sed -E 's/.*[][]{3,}([a-z][a-z0-9_-]+)([@|].*)?$/\1/')
  if [ "$cand" != "$sn" ] && [[ "$cand" =~ ^[a-z][a-z0-9_-]+$ ]]; then
    echo "$cand"
    return 0
  fi
  if [[ "$sn" =~ ^[a-z][a-z0-9_-]+$ ]]; then
    echo "$sn"
    return 0
  fi
  return 1
}

# Check if a lane has at least one existing bead. Returns 0 if real, 1 if phantom.
# Phantom = the resolved lane name has no labeled beads anywhere in the project,
# which usually means a typo'd tmux session name or an unbootstrapped workstream.
_il_bd_lane_has_beads() {
  local lane="$1"
  [ -z "$lane" ] && return 1
  command -v bd > /dev/null 2>&1 || return 0  # No bd → can't verify; assume real
  # timeout uses PATH lookup (not shell function lookup), so this hits the
  # bd binary directly, not the wrapper function. `command` would be wrong
  # here because timeout can't run shell builtins.
  local count
  count=$(timeout 2 bd list --label="$lane" --limit 1 --json --quiet 2>/dev/null \
    | jq 'length' 2>/dev/null)
  [ "${count:-0}" -gt 0 ]
}

# List up to 5 existing labels sharing a prefix with the input.
# Used in phantom-lane suggestions to catch typos like interlyze→interspect.
_il_bd_lane_suggestions() {
  local input="$1"
  local prefix="${input:0:5}"
  [ -z "$prefix" ] && return 1
  command -v bd > /dev/null 2>&1 || return 1
  timeout 3 bd list --json --quiet 2>/dev/null \
    | jq -r '[.[].labels[]?] | unique | .[]' 2>/dev/null \
    | grep -E "^${prefix}" \
    | grep -v -F -x "$input" \
    | head -5 \
    | tr '\n' ' '
}

# Print a stderr warning when a resolved lane appears to be a phantom.
# Always prints (not gated by BD_LANE_DEBUG) — phantoms are exceptional.
_il_bd_warn_phantom() {
  local lane="$1" source="$2"
  echo "bd-lane: WARNING: lane='${lane}' (from ${source}) has 0 existing beads — possible phantom (typo? unbootstrapped lane?)" >&2
  local suggestions
  suggestions=$(_il_bd_lane_suggestions "$lane" 2>/dev/null)
  if [ -n "$suggestions" ]; then
    echo "bd-lane: did you mean: ${suggestions% }" >&2
  fi
  echo "bd-lane: applying anyway — pass --no-lane to skip, or BD_LANE_STRICT=1 to fall through to Haiku" >&2
}

# Detect lane from sideband file, then tmux. Echoes lane and source name.
_il_bd_detect_lane_local() {
  local sid="${CLAUDE_SESSION_ID:-}"
  if [ -n "$sid" ]; then
    local sf="${INTERBAND_ROOT:-$HOME/.interband}/interphase/lane/${sid}.json"
    if [ -f "$sf" ]; then
      local lane
      lane=$(jq -r '.payload.lane // empty' "$sf" 2>/dev/null)
      if [ -n "$lane" ]; then
        echo "$lane sideband"
        return 0
      fi
    fi
  fi
  if [ -n "${TMUX:-}" ] && command -v tmux > /dev/null 2>&1; then
    local sn
    sn=$(tmux display-message -p '#S' 2>/dev/null)
    local lane
    if lane=$(_il_bd_parse_session_name "$sn"); then
      echo "$lane tmux"
      return 0
    fi
  fi
  return 1
}

# Build the candidate-lane vocabulary for Haiku classification.
# Combines tmux-derived lanes with BD_LANE_VOCAB if set.
_il_bd_lane_vocab() {
  if [ -n "${BD_LANE_VOCAB:-}" ]; then
    echo "$BD_LANE_VOCAB"
    return 0
  fi
  local lanes=""
  if command -v tmux > /dev/null 2>&1; then
    while IFS= read -r sn; do
      local cand
      if cand=$(_il_bd_parse_session_name "$sn"); then
        lanes="${lanes}${cand},"
      fi
    done < <(tmux list-sessions -F '#S' 2>/dev/null | sort -u)
  fi
  # Strip trailing comma; fall back to a hardcoded default if empty.
  lanes="${lanes%,}"
  echo "${lanes:-graph,interflux,strategy,usability,interlyze,interweave,orchestration,ux}"
}

# Classify a title via Haiku 4.5; echoes a lane name on success.
_il_bd_classify_haiku() {
  local title="$1"
  [ -z "$title" ] && return 1
  command -v claude > /dev/null 2>&1 || return 1
  local vocab
  vocab=$(_il_bd_lane_vocab)
  local prompt="Classify this task into exactly one of these lanes: ${vocab}, or 'none' if no lane fits.
Reply with ONLY the lane name in lowercase. No prose, no punctuation, no markdown.

Title: ${title}"
  local out
  out=$(timeout 10 claude -p --model claude-haiku-4-5 "$prompt" 2>/dev/null \
    | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  [ -z "$out" ] || [ "$out" = "none" ] && return 1
  case ",${vocab}," in
    *",${out},"*) echo "$out"; return 0 ;;
  esac
  return 1
}

# Scan create args for: --labels presence, --no-lane flag, title, description.
# Outputs a tab-separated record: HAS_LABELS\tHAS_NO_LANE\tTITLE\tDESCRIPTION
_il_bd_scan_args() {
  local has_labels=0 has_no_lane=0 title="" desc=""
  local capture_next="" past_doubledash=0
  for a in "$@"; do
    if [ "$past_doubledash" = "1" ]; then
      [ -z "$title" ] && title="$a"
      continue
    fi
    if [ "$capture_next" = "desc" ]; then
      desc="$a"
      capture_next=""
      continue
    fi
    if [ "$capture_next" = "skip" ]; then
      capture_next=""
      continue
    fi
    case "$a" in
      --) past_doubledash=1 ;;
      --no-lane) has_no_lane=1 ;;
      --labels|-l) has_labels=1; capture_next="skip" ;;
      --labels=*|-l=*) has_labels=1 ;;
      --description|-d) capture_next="desc" ;;
      --description=*) desc="${a#*=}" ;;
      -d=*) desc="${a#*=}" ;;
      --*=*|-?=*) capture_next="" ;;
      --*|-?) capture_next="skip" ;;
      *)
        if [ -z "$title" ] && [[ "$a" != -* ]]; then
          title="$a"
        fi
        ;;
    esac
  done
  printf '%s\t%s\t%s\t%s\n' "$has_labels" "$has_no_lane" "$title" "$desc"
}

bd() {
  if [ "${BD_LANE_DISABLE:-0}" = "1" ]; then
    _il_bd_real "$@"
    return $?
  fi
  if [ "$#" -eq 0 ] || { [ "$1" != "create" ] && [ "$1" != "new" ]; }; then
    _il_bd_real "$@"
    return $?
  fi

  local sub="$1"; shift
  local scan
  scan=$(_il_bd_scan_args "$@")
  local has_labels has_no_lane title desc
  IFS=$'\t' read -r has_labels has_no_lane title desc <<<"$scan"

  # Strip --no-lane before forwarding.
  if [ "$has_no_lane" = "1" ]; then
    local args=()
    for a in "$@"; do
      [ "$a" != "--no-lane" ] && args+=("$a")
    done
    _il_bd_log "skipped (--no-lane)"
    _il_bd_real "$sub" "${args[@]}"
    return $?
  fi

  if [ "$has_labels" = "1" ]; then
    _il_bd_log "skipped (--labels supplied)"
    _il_bd_real "$sub" "$@"
    return $?
  fi

  local lane="" source=""
  local detected
  if detected=$(_il_bd_detect_lane_local); then
    lane="${detected% *}"
    source="${detected##* }"
  elif [ -n "$title" ]; then
    if lane=$(_il_bd_classify_haiku "$title"); then
      source="haiku"
    fi
  fi

  # Phantom-lane check: warn if the resolved lane has no existing beads.
  # Default = warn but still apply (don't break new-lane bootstrap).
  # BD_LANE_STRICT=1 = warn + drop the lane and fall through to Haiku/no-tag.
  if [ -n "$lane" ] && ! _il_bd_lane_has_beads "$lane"; then
    _il_bd_warn_phantom "$lane" "$source"
    if [ "${BD_LANE_STRICT:-0}" = "1" ]; then
      _il_bd_log "strict mode: dropping phantom lane, retrying with Haiku"
      lane=""
      if [ -n "$title" ] && lane=$(_il_bd_classify_haiku "$title"); then
        source="haiku-fallback"
        # Re-check the Haiku result (Haiku vocab can also include phantom names)
        if ! _il_bd_lane_has_beads "$lane"; then
          _il_bd_warn_phantom "$lane" "$source"
          lane=""
        fi
      fi
    fi
  fi

  if [ -n "$lane" ]; then
    _il_bd_log "lane=${lane} (${source})"
    _il_bd_real "$sub" "$@" --labels="$lane"
    return $?
  fi
  _il_bd_log "no lane resolved"
  _il_bd_real "$sub" "$@"
}

# Export functions so child non-interactive shells (e.g. Claude Code's Bash tool,
# scripts spawned via `bash -c`) inherit the wrapper. Bash propagates exported
# functions through the BASH_FUNC_<name>%% env vars.
export -f bd \
  _il_bd_real _il_bd_log \
  _il_bd_parse_session_name _il_bd_detect_lane_local \
  _il_bd_lane_vocab _il_bd_classify_haiku \
  _il_bd_scan_args \
  _il_bd_lane_has_beads _il_bd_lane_suggestions _il_bd_warn_phantom 2>/dev/null || true
