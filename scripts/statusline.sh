#!/bin/bash

# Claude Code statusline — workflow-aware with dispatch state tracking
# Priority: dispatch state > transcript phase > clodex mode > default

# Read JSON input from stdin
input=$(cat)

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
for state_file in /tmp/clavain-dispatch-*.json; do
  [ -f "$state_file" ] || continue
  # Verify the owning process is still alive
  pid="${state_file##*-}"
  pid="${pid%.json}"
  if kill -0 "$pid" 2>/dev/null; then
    name=$(jq -r '.name // "codex"' "$state_file" 2>/dev/null)
    dispatch_label="Clodex: $name"
    break
  else
    # Stale state file — owning process died without cleanup
    rm -f "$state_file"
  fi
done

# --- Layer 1.5: Check for active bead context ---
bead_label=""
if [ -z "$dispatch_label" ]; then
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
          bead_label="$bead_id"
          [ -n "$bead_phase" ] && bead_label="$bead_label ($bead_phase)"
        fi
      fi
    fi
  fi
fi

# --- Layer 2: Scan transcript for last workflow phase ---
phase_label=""
if [ -z "$dispatch_label" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Find last Skill invocation — scan backwards, stop at first match
  skill_line=$(tac "$transcript" 2>/dev/null | grep -m1 '"Skill"' || true)
  if [ -n "$skill_line" ]; then
    # Extract skill name from the tool_use input
    skill_name=$(echo "$skill_line" | grep -oP '"skill"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"skill"\s*:\s*"//;s/".*//')
    if [ -n "$skill_name" ]; then
      # Strip namespace prefix (e.g., "clavain:brainstorm" -> "brainstorm")
      skill_short="${skill_name##*:}"
      case "$skill_short" in
        brainstorm*)        phase_label="Brainstorming" ;;
        strategy)           phase_label="Strategy" ;;
        write-plan)         phase_label="Planning" ;;
        flux-drive)         phase_label="Reviewing" ;;
        work|execute-plan)  phase_label="Executing" ;;
        quality-gates)      phase_label="Quality Gates" ;;
        resolve)            phase_label="Resolving" ;;
        landing-a-change)   phase_label="Shipping" ;;
        clodex*)            phase_label="Dispatching" ;;
        compound|engineering-docs) phase_label="Documenting" ;;
        interpeer|debate)   phase_label="Peer Review" ;;
        smoke-test)         phase_label="Testing" ;;
        doctor|heal-skill)  phase_label="Diagnostics" ;;
      esac
    fi
  fi
fi

# --- Layer 3: Check for clodex mode flag (always visible when active) ---
clodex_suffix=""
if [ -f "$project_dir/.claude/clodex-toggle.flag" ]; then
  clodex_suffix=" with \033[38;5;210mC\033[38;5;216ml\033[38;5;228mo\033[38;5;157md\033[38;5;111me\033[38;5;183mx\033[0m"
fi

# --- Build status line ---
status_line="[$model$clodex_suffix] $project"

if [ -n "$git_branch" ]; then
  status_line="$status_line:$git_branch"
fi

# Append workflow context (dispatch > bead + phase)
if [ -n "$dispatch_label" ]; then
  status_line="$status_line | $dispatch_label"
else
  # Bead and phase are shown together: "Clavain-021h (planned) | Executing"
  if [ -n "$bead_label" ]; then
    status_line="$status_line | $bead_label"
  fi
  if [ -n "$phase_label" ]; then
    status_line="$status_line | $phase_label"
  fi
fi

echo -e "$status_line"
