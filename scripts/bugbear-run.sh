#!/bin/bash
# Sends one automation command to the running app and prints its result.
#
#   scripts/bugbear-run.sh <command> [timeout seconds]
#
# Needs the automation hook on (scripts/e2e.sh turns it on; see DevTools/Automation.swift).
set -uo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
LOG="$HOME/Library/Logs/Bugbear/bugbear.log"
command="$1"
timeout="${2:-60}"
before=$(grep -cF "AUTOMATION $command →" "$LOG" 2>/dev/null || true)
scripts/bugbear-command.sh "$command"
waited=0
while [ "$waited" -lt "$((timeout * 4))" ]; do
    now=$(grep -cF "AUTOMATION $command →" "$LOG" 2>/dev/null || true)
    if [ "$now" -gt "$before" ]; then
        grep -F "AUTOMATION $command →" "$LOG" | tail -1 | sed 's/.*→ //'
        exit 0
    fi
    sleep 0.25
    waited=$((waited + 1))
done
echo "TIMEOUT"
exit 1
