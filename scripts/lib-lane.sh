#!/usr/bin/env bash
# lib-lane.sh — shared lane-detection helpers for interline.
# Sourced by both statusline.sh and bd-lane-wrapper.sh; do not duplicate
# the parser elsewhere — extend this file instead.
#
# Public functions (all use the _il_lane_ prefix):
#   _il_lane_parse_session_name <name>  → echoes lane on stdout
#   _il_lane_tmux_session_name          → echoes current tmux session name
#   _il_lane_resolve                    → echoes "lane source" (sideband|tmux)
#
# All return 0 on match, 1 on failure. No side effects on load.

# Extract a lane from a tmux-style session name.
# Recognized: ...[[[<lane>@..., ...]]]<lane>|..., or ...[[[<lane>$ (no terminator).
# The trailing terminator is optional, so sessions named without an `@<model>`
# suffix (e.g. `[warp[[sylveste[[[feedback`) still resolve.
# Bare alphanumeric session names are also returned as-is.
_il_lane_parse_session_name() {
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

# Get current tmux session name, or fail if not in tmux.
_il_lane_tmux_session_name() {
  [ -n "${TMUX:-}" ] || return 1
  command -v tmux > /dev/null 2>&1 || return 1
  tmux display-message -p '#S' 2>/dev/null
}

# Resolve the current session's lane.
# Order: sideband file → tmux session name parse.
# Echoes "lane source" (e.g. "interspect tmux") on success; nothing on failure.
# Source name is one of: sideband, tmux.
_il_lane_resolve() {
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
  local sn
  sn=$(_il_lane_tmux_session_name) || return 1
  local lane
  if lane=$(_il_lane_parse_session_name "$sn"); then
    echo "$lane tmux"
    return 0
  fi
  return 1
}
