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
# Recognized: ...[[[<lane>@... or ...]]]<lane>@... or ...[[[<lane>|... etc.
# Bare alphanumeric session names are also returned as-is.
_il_bd_parse_session_name() {
  local sn="$1"
  [ -z "$sn" ] && return 1
  local cand
  cand=$(echo "$sn" | sed -E 's/.*[][]{3,}([a-z][a-z0-9_-]+)[@|].*/\1/')
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

  if [ -n "$lane" ]; then
    _il_bd_log "lane=${lane} (${source})"
    _il_bd_real "$sub" "$@" --labels="$lane"
    return $?
  fi
  _il_bd_log "no lane resolved"
  _il_bd_real "$sub" "$@"
}
