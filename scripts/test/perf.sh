#!/bin/bash
# Performance check of the running app: CPU and memory while idle with the buffer,
# while recording with the drawing overlay, and how long saving a clip takes.
#
#   scripts/test/perf.sh
#
# Needs Screen Recording permission. Uses the automation hook like scripts/test/e2e.sh.
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi
# DEFAULT_BUNDLE_ID for a .env without APP_BUNDLE_ID.
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/app-name.sh"
BUNDLE_ID="${APP_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
# shellcheck disable=SC1091
source "$ROOT/scripts/test/lib/test-app.sh"
LOG="$HOME/Library/Logs/$APP_NAME/$APP_NAME.log"
# Reads only this run's lines of the person's log (run_log), never deletes it.
# shellcheck disable=SC1091
source "$ROOT/scripts/test/lib/run-log.sh"
FAILURES=0

# Limits for a "fast and smooth" verdict.
MAX_IDLE_CPU=15        # % of one core, average
MAX_RECORDING_CPU=15   # % of one core, average (about 5 on a still screen since 0.10.0)
MAX_AREA_RECORDING_CPU=15  # % of one core, average, an area on the built-in display with every display in the buffer
MAX_MEMORY_MB=350
MAX_SAVE_SECONDS=3     # for a 30 s clip

sample() {
    # sample <seconds> → prints "avgCPU maxCPU maxRSSMB"
    local seconds="$1"
    local pid
    pid=$(pgrep -x "$APP_NAME" | head -1)
    local total=0
    local peak=0
    local memory=0
    for _ in $(seq 1 "$seconds"); do
        local line
        line=$(ps -o %cpu=,rss= -p "$pid" 2>/dev/null)
        local cpu
        cpu=$(echo "$line" | awk '{print $1}')
        local rss
        rss=$(echo "$line" | awk '{print int($2 / 1024)}')
        total=$(python3 -c "print($total + ${cpu:-0})")
        peak=$(python3 -c "print(max($peak, ${cpu:-0}))")
        if [ "${rss:-0}" -gt "$memory" ]; then memory=$rss; fi
        sleep 1
    done
    python3 -c "print(f'{$total / $seconds:.1f} {$peak:.1f} $memory')"
}

verdict() {
    # verdict <name> <value> <limit>
    if python3 -c "import sys; sys.exit(0 if float('$2') <= float('$3') else 1)"; then
        echo "PASS  $1: $2 (limit $3)"
    else
        echo "FAIL  $1: $2 (limit $3)"
        FAILURES=$((FAILURES + 1))
    fi
}

echo "==> build"
build_test_app || exit 1
# Quit the person's copy of the app and keep a copy of their settings before any test setting is written.
quit_running_app
defaults write "$BUNDLE_ID" automationEnabled -bool true
# Editor choices made by the tests go to a store of their own (EditorMemory); start it empty.
defaults delete "$BUNDLE_ID.tests" 2>/dev/null
defaults write "$BUNDLE_ID" recordSystemAudio -bool false
defaults write "$BUNDLE_ID" recordMicrophone -bool false
log_lines_before=$(log_line_count)
log_first_before=$(log_first_line)
open "$TEST_APP"
sleep 8

echo "==> idle with the buffer running (20 s, screen mostly static)"
read -r idle_avg idle_peak idle_mem <<< "$(sample 20)"
verdict "idle CPU average %" "$idle_avg" "$MAX_IDLE_CPU"
echo "      peak ${idle_peak}%"
verdict "idle memory MB" "$idle_mem" "$MAX_MEMORY_MB"

echo "==> recording with the drawing overlay (15 s)"
scripts/dev/app-command.sh record-start; sleep 2
scripts/dev/app-command.sh draw-toggle; sleep 1
read -r rec_avg rec_peak rec_mem <<< "$(sample 15)"
verdict "recording CPU average %" "$rec_avg" "$MAX_RECORDING_CPU"
echo "      peak ${rec_peak}%"
verdict "recording memory MB" "$rec_mem" "$MAX_MEMORY_MB"
scripts/dev/app-command.sh draw-toggle; sleep 1
scripts/dev/app-command.sh record-stop; sleep 8
scripts/dev/app-command.sh close-windows; sleep 2

echo "==> recording an area on the built-in display (15 s)"
# Every display is in the buffer for an area recording; only the built-in one, which the area is on,
# runs at native resolution and the recording frame rate.
display_count=$(scripts/dev/app-run.sh screens 10 | tr ';' '\n' | grep -c ':')
if [ "$display_count" -lt 2 ]; then echo "      (one display: the buffer has only the built-in one)"; fi
scripts/dev/app-command.sh "record-area:0.2,0.2,0.4,0.4:builtin"; sleep 3
echo "      buffers $(scripts/dev/app-run.sh buffer-sizes 10)"
read -r area_avg area_peak area_mem <<< "$(sample 15)"
verdict "area recording CPU average %" "$area_avg" "$MAX_AREA_RECORDING_CPU"
echo "      peak ${area_peak}%"
verdict "area recording memory MB" "$area_mem" "$MAX_MEMORY_MB"
scripts/dev/app-command.sh record-stop; sleep 8
scripts/dev/app-command.sh close-windows; sleep 2

echo "==> save the last 30 s"
sleep 10
scripts/dev/app-command.sh save:30
sleep 10
start=$(run_log | grep "save from buffer: last 30" | tail -1 | awk '{print $2}')
end=$(run_log | grep "clip exported" | tail -1 | awk '{print $2}')
save_seconds=$(python3 -c "
from datetime import datetime
fmt = '%H:%M:%S.%f'
print(round((datetime.strptime('$end', fmt) - datetime.strptime('$start', fmt)).total_seconds(), 2))
" 2>/dev/null || echo 99)
verdict "save 30 s clip, seconds" "$save_seconds" "$MAX_SAVE_SECONDS"
scripts/dev/app-command.sh close-windows; sleep 2

echo "==> menu bar stays responsive (automation round trip)"
before=$(date +%s.%N)
scripts/dev/app-command.sh status
for _ in $(seq 1 50); do
    if [ "$(run_log | grep -c "AUTOMATION status")" -gt 0 ]; then break; fi
    sleep 0.1
done
after=$(date +%s.%N)
round_trip=$(python3 -c "print(round($after - $before, 2))")
verdict "command round trip, seconds" "$round_trip" 1

echo "==> core speed"
"$(swift build -c release --show-bin-path)/App" --perf-core 2>/dev/null

errors=$(run_log | grep -c "ERROR" || true)
if [ "$errors" = "0" ]; then echo "PASS  no errors in the log"; else echo "FAIL  $errors errors in the log"; FAILURES=$((FAILURES + 1)); fi

defaults write "$BUNDLE_ID" automationEnabled -bool false
echo
if [ "$FAILURES" = "0" ]; then echo "ALL PERFORMANCE CHECKS PASSED"; else echo "$FAILURES PERFORMANCE CHECK(S) FAILED"; fi
[ "$FAILURES" = "0" ]
