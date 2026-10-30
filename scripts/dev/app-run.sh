#!/bin/bash
# Sends one automation command to the running app and prints its result.
#
#   scripts/dev/app-run.sh <command> [timeout seconds]
#
# Needs the automation hook on (scripts/test/e2e.sh turns it on; see DevTools/Automation.swift).
# The command goes out with " #id=<token>" at its end; the app writes the result to a file named
# after the token in its automation/results folder. This script reads the file, prints it and deletes it.
set -uo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/app-name.sh"
RESULTS="$HOME/Library/Application Support/$APP_NAME/automation/results"
command="$1"
timeout="${2:-60}"
# Every call is its own process, so the same command sent twice in a row still gets two tokens.
token="$$-$RANDOM-$RANDOM"
result_file="$RESULTS/$token"
scripts/dev/app-command.sh "$command #id=$token"
waited=0
limit=$((timeout * 20))
while [ "$waited" -lt "$limit" ]; do
    if [ -f "$result_file" ]; then
        # One line with its newline, as the log path printed it: `$R screens | tr ';' '\n' | wc -l`
        # and `while read` loops count the last item too. $(...) drops a newline the file already has.
        printf '%s\n' "$(cat "$result_file")"
        rm -f "$result_file"
        exit 0
    fi
    sleep 0.05
    waited=$((waited + 1))
done
echo "TIMEOUT"
exit 1
