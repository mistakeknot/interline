#!/usr/bin/env bash
set -uo pipefail
trap 'exit 0' ERR
# interline session-start hook — source interbase and nudge companions
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$HOOK_DIR/interbase-stub.sh"

ib_session_status
ib_nudge_companion "intercheck" "Adds context pressure indicator to your statusline"
