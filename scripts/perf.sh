#!/bin/bash
# Performance check of the running app: CPU and memory while idle with the buffer,
# while recording with the drawing overlay, and how long saving a clip takes.
#
#   scripts/perf.sh
#
# Needs Screen Recording permission. Uses the automation hook like scripts/e2e.sh.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi
BUNDLE_ID="${BUGBEAR_BUNDLE_ID:-io.github.bugbear.app}"
LOG="$HOME/Library/Logs/Bugbear/bugbear.log"
FAILURES=0

# Limits for a "fast and smooth" verdict.
MAX_IDLE_CPU=15        # % of one core, average
MAX_RECORDING_CPU=30   # % of one core, average
MAX_MEMORY_MB=350
MAX_SAVE_SECONDS=3     # for a 30 s clip

sample() {
    # sample <seconds> → prints "avgCPU maxCPU maxRSSMB"
    local seconds="$1"
    local pid
    pid=$(pgrep -x Bugbear | head -1)
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
scripts/build-app.sh >/dev/null 2>&1 || { echo "build failed"; exit 1; }
defaults write "$BUNDLE_ID" automationEnabled -bool true
defaults write "$BUNDLE_ID" recordSystemAudio -bool false
defaults write "$BUNDLE_ID" recordMicrophone -bool false
pkill -x Bugbear 2>/dev/null; sleep 1
rm -f "$LOG"
open "$ROOT/build/Bugbear.app"
sleep 8

echo "==> idle with the buffer running (20 s, screen mostly static)"
read -r idle_avg idle_peak idle_mem <<< "$(sample 20)"
verdict "idle CPU average %" "$idle_avg" "$MAX_IDLE_CPU"
echo "      peak ${idle_peak}%"
verdict "idle memory MB" "$idle_mem" "$MAX_MEMORY_MB"

echo "==> recording with the drawing overlay (15 s)"
scripts/bugbear-command.sh record-start; sleep 2
scripts/bugbear-command.sh draw-toggle; sleep 1
read -r rec_avg rec_peak rec_mem <<< "$(sample 15)"
verdict "recording CPU average %" "$rec_avg" "$MAX_RECORDING_CPU"
echo "      peak ${rec_peak}%"
verdict "recording memory MB" "$rec_mem" "$MAX_MEMORY_MB"
scripts/bugbear-command.sh draw-toggle; sleep 1
scripts/bugbear-command.sh record-stop; sleep 8
scripts/bugbear-command.sh close-windows; sleep 2

echo "==> save the last 30 s"
sleep 10
scripts/bugbear-command.sh save:30
sleep 10
start=$(grep "save from buffer: last 30" "$LOG" | tail -1 | awk '{print $2}')
end=$(grep "clip exported" "$LOG" | tail -1 | awk '{print $2}')
save_seconds=$(python3 -c "
from datetime import datetime
fmt = '%H:%M:%S.%f'
print(round((datetime.strptime('$end', fmt) - datetime.strptime('$start', fmt)).total_seconds(), 2))
" 2>/dev/null || echo 99)
verdict "save 30 s clip, seconds" "$save_seconds" "$MAX_SAVE_SECONDS"
scripts/bugbear-command.sh close-windows; sleep 2

echo "==> menu bar stays responsive (automation round trip)"
before=$(date +%s.%N)
scripts/bugbear-command.sh status
for _ in $(seq 1 50); do
    if [ "$(grep -c "AUTOMATION status" "$LOG")" -gt 0 ]; then break; fi
    sleep 0.1
done
after=$(date +%s.%N)
round_trip=$(python3 -c "print(round($after - $before, 2))")
verdict "command round trip, seconds" "$round_trip" 1

echo "==> core speed"
"$(swift build -c release --show-bin-path)/Bugbear" --perf-core 2>/dev/null

errors=$(grep -c "ERROR" "$LOG" || true)
if [ "$errors" = "0" ]; then echo "PASS  no errors in the log"; else echo "FAIL  $errors errors in the log"; FAILURES=$((FAILURES + 1)); fi

defaults write "$BUNDLE_ID" automationEnabled -bool false
echo
if [ "$FAILURES" = "0" ]; then echo "ALL PERFORMANCE CHECKS PASSED"; else echo "$FAILURES PERFORMANCE CHECK(S) FAILED"; fi
[ "$FAILURES" = "0" ]
