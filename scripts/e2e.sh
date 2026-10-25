#!/bin/bash
# End-to-end checks against the real app and real screen capture.
#
#   scripts/e2e.sh            build, launch, run every scenario, print PASS/FAIL
#
# Needs Screen Recording permission for Bugbear (granted once in System Settings).
# Turns on the local automation hook for the run and turns it off afterwards.
# The microphone and camera are skipped: they would show permission prompts.
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
PASSES=0

pass() { echo "PASS  $1"; PASSES=$((PASSES + 1)); }
fail() { echo "FAIL  $1 ${2:-}"; FAILURES=$((FAILURES + 1)); }

# Sends a command and waits for its "AUTOMATION <command> →" line. Prints the result.
run() {
    local command="$1"
    local timeout="${2:-60}"
    local before
    before=$(grep -c "AUTOMATION $command →" "$LOG" 2>/dev/null || true)
    scripts/bugbear-command.sh "$command"
    local waited=0
    while [ "$waited" -lt "$timeout" ]; do
        local now
        now=$(grep -c "AUTOMATION $command →" "$LOG" 2>/dev/null || true)
        if [ "$now" -gt "$before" ]; then
            grep "AUTOMATION $command →" "$LOG" | tail -1 | sed 's/.*→ //'
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "TIMEOUT"
}

field() { echo "$1" | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

# Pulls file= out of a result; file paths contain spaces, so take everything after "file=".
file_of() { echo "$1" | sed -n 's/.*file=//p'; }

media_duration() { avmediainfo "$1" 2>/dev/null | grep -m1 "^Duration" | sed -E 's/Duration: ([0-9.]+).*/\1/'; }
track_count() { avmediainfo "$1" 2>/dev/null | grep -c "^Track [0-9]*: $2"; }

near() { python3 -c "import sys; sys.exit(0 if abs(float('$1') - float('$2')) <= float('$3') else 1)" 2>/dev/null; }
at_least() { python3 -c "import sys; sys.exit(0 if float('$1') >= float('$2') else 1)" 2>/dev/null; }

echo "==> build"
scripts/build-app.sh >/dev/null 2>&1 || { echo "build failed"; exit 1; }
defaults write "$BUNDLE_ID" automationEnabled -bool true
defaults write "$BUNDLE_ID" recordSystemAudio -bool false
defaults write "$BUNDLE_ID" recordMicrophone -bool false
defaults write "$BUNDLE_ID" bufferMinutes -int 3
defaults write "$BUNDLE_ID" startBufferOnLaunch -bool true
# Update checks go to a local file server instead of GitHub.
FEED_DIR="$ROOT/build/e2e-update-feed"
mkdir -p "$FEED_DIR"
printf '{"status":"ahead","ahead_by":2,"commits":[{"sha":"1111111aaaa","commit":{"message":"First change"}},{"sha":"2222222bbbb","commit":{"message":"Second change"}}]}' > "$FEED_DIR/compare.json"
printf 'WhatsNewRelease(id: 99, version: "99.0.0", title: "Future", items: [])\n' > "$FEED_DIR/catalog.swift"
python3 -m http.server 8765 --bind 127.0.0.1 --directory "$FEED_DIR" >/dev/null 2>&1 &
FEED_PID=$!
defaults write "$BUNDLE_ID" updateCompareURL "http://127.0.0.1:8765/compare.json"
defaults write "$BUNDLE_ID" updateCatalogURL "http://127.0.0.1:8765/catalog.swift"
pkill -x Bugbear 2>/dev/null; sleep 1
rm -f "$LOG"
open "$ROOT/build/Bugbear.app"
echo "==> waiting 20 s with a mostly static screen"
sleep 20

# 1. Buffer runs and fills even when nothing moves.
status=$(run status)
echo "      $status"
if echo "$status" | grep -q "^running"; then pass "buffer is running"; else fail "buffer is running" "$status"; fi
covered=$(field "$status" covered)
if at_least "${covered:-0}" 15; then pass "buffer covers a static screen (${covered}s)"; else fail "buffer covers a static screen" "covered=$covered"; fi

# 2. Save the last 8 seconds.
result=$(run save:8 90)
echo "      $result"
file=$(file_of "$result")
if [ -n "$file" ] && [ -f "$file" ]; then
    duration=$(media_duration "$file")
    if near "$duration" 8 0.4; then pass "save 8 s → ${duration}s clip"; else fail "save 8 s duration" "got $duration"; fi
    if [ "$(track_count "$file" Video)" = "1" ]; then pass "clip has a video track"; else fail "clip has a video track"; fi
else
    fail "save 8 s produced a file" "$result"
fi
sleep 3
if grep -q "buffer\[.*\] stopping" "$LOG"; then fail "buffer keeps running after the editor opens" "it restarted"; else pass "buffer keeps running after the editor opens"; fi
run close-windows >/dev/null

# 3. Save the whole buffer: should be about as long as what the buffer holds.
status=$(run status)
covered=$(field "$status" covered)
result=$(run save:180 120)
file=$(file_of "$result")
if [ -n "$file" ] && [ -f "$file" ]; then
    duration=$(media_duration "$file")
    if near "$duration" "$covered" 2.5; then pass "save whole buffer → ${duration}s (buffer held ${covered}s)"; else fail "save whole buffer" "got $duration, buffer held $covered"; fi
else
    fail "save whole buffer produced a file" "$result"
fi
run close-windows >/dev/null

# 4. Recording with a pause: the pause is cut out.
wall_start=$(date +%s.%N)
started=$(run record-start)
outline=$(field "$started" outline)
screens=$(field "$started" screens)
if [ -n "$outline" ] && [ "$outline" = "$screens" ]; then pass "recording outline on every screen ($outline)"; else fail "recording outline" "$started"; fi
sleep 4
run record-pause >/dev/null
sleep 3
run record-resume >/dev/null
draw=$(run draw-toggle)
if echo "$draw" | grep -q "visible=true drawing=true"; then pass "draw on screen during recording"; else fail "draw on screen during recording" "$draw"; fi
sleep 3
run draw-toggle >/dev/null
wall_stop=$(date +%s.%N)
result=$(run record-stop 120)
echo "      $result"
elapsed=$(field "$result" elapsed)
file=$(file_of "$result")
if [ -n "$file" ] && [ -f "$file" ]; then
    duration=$(media_duration "$file")
    if near "$duration" "$elapsed" 0.6; then pass "recording ${duration}s matches recorded time ${elapsed}s (pause removed)"; else fail "recording length" "file $duration vs elapsed $elapsed"; fi
    wall=$(python3 -c "print(round($wall_stop - $wall_start, 2))")
    # The 3 s pause must be missing from the file.
    if at_least "$(python3 -c "print($wall - 2.5)")" "$duration"; then pass "pause is cut out (${duration}s file, ${wall}s wall time)"; else fail "pause is cut out" "file $duration vs wall $wall"; fi
else
    fail "recording produced a file" "$result"
fi
run close-windows >/dev/null

# 5. Video editor pipeline on the real recording.
result=$(run export-latest 180)
echo "      $result"
expected=$(field "$result" expected)
exported=$(field "$result" exported)
if [ -n "$expected" ] && near "$exported" "$expected" 0.4; then pass "editor export ${exported}s (expected ${expected}s)"; else fail "editor export" "$result"; fi

# 6. System audio ends up in the clip.
run setting:recordSystemAudio:true >/dev/null
run buffer-start >/dev/null
sleep 3
( for _ in 1 2 3 4; do afplay /System/Library/Sounds/Glass.aiff; done ) &
sleep 5
result=$(run save:6 90)
file=$(file_of "$result")
run setting:recordSystemAudio:false >/dev/null
if [ -n "$file" ] && [ -f "$file" ]; then
    if [ "$(track_count "$file" Sound)" = "1" ]; then pass "system audio recorded"; else fail "system audio recorded" "no audio track"; fi
else
    fail "save with system audio produced a file" "$result"
fi
run close-windows >/dev/null
run buffer-start >/dev/null

# 7. Screenshots.
result=$(run screenshot-full 60)
file=$(file_of "$result")
if [ -n "$file" ] && [ -f "$file" ] && sips -g pixelWidth "$file" >/dev/null 2>&1; then pass "full-screen screenshot"; else fail "full-screen screenshot" "$result"; fi
run close-windows >/dev/null
result=$(run screenshot-all 60)
file=$(file_of "$result")
if [ -n "$file" ] && [ -f "$file" ]; then pass "all-displays screenshot ($(sips -g pixelWidth "$file" | tail -1 | awk '{print $2}') px wide)"; else fail "all-displays screenshot" "$result"; fi
run close-windows >/dev/null

# 8. A marker makes the next save reach back to it.
run mark >/dev/null
sleep 25
result=$(run save:5 90)
echo "      $result"
file=$(file_of "$result")
if [ -n "$file" ] && [ -f "$file" ]; then
    duration=$(media_duration "$file")
    # Marked 25 s ago, plus 5 s of lead-in: about 30 s instead of 5.
    if near "$duration" 30 1.5; then pass "save after ⌥⇧M reaches back to the marker (${duration}s)"; else fail "save after a marker" "got $duration, expected about 30"; fi
else
    fail "save after a marker produced a file" "$result"
fi
run close-windows >/dev/null

# 9. A crash report saves the minute before the crash, without opening the editor.
crash_folder="$ROOT/build/e2e-crash-reports"
rm -rf "$crash_folder"
mkdir -p "$crash_folder"
run "crash-watch:$crash_folder" >/dev/null
sleep 1
crash_time=$(date -v-1S "+%Y-%m-%d %H:%M:%S.00 %z")
printf '{"app_name":"E2E Crasher","timestamp":"%s","bundleID":"io.github.bugbear.e2e","bug_type":"309","name":"E2E Crasher"}\n{}\n' "$crash_time" > "$crash_folder/E2E Crasher-test.ips"
saved=""
for _ in $(seq 1 60); do
    saved=$(grep "crash clip saved" "$LOG" | tail -1)
    if [ -n "$saved" ]; then break; fi
    sleep 1
done
if [ -n "$saved" ]; then
    capture_id=$(echo "$saved" | sed 's/.*→ //')
    capture_folder=$(find "$HOME/Library/Application Support/Bugbear" -type d -name "$capture_id" 2>/dev/null | head -1)
    duration=$(media_duration "$capture_folder/original.mp4")
    if at_least "${duration:-0}" 30; then pass "crash saves the time before it (${duration}s clip)"; else fail "crash clip length" "got $duration"; fi
    if [ -f "$capture_folder/crash-report.ips" ]; then pass "crash report kept next to the clip"; else fail "crash report kept next to the clip" "$capture_folder"; fi
else
    fail "crash detected and saved" "no 'crash clip saved' in the log"
fi
rm -rf "$crash_folder"

# 10. The system log collector ran for the saved clips.
if grep -q "system log for .*: [0-9]* lines" "$LOG"; then pass "system log collected ($(grep "system log for" "$LOG" | tail -1 | sed 's/.*system log for //'))"; else fail "system log collected" "no 'system log for' line"; fi

# 11. Update check finds a newer release and lists its commits; the same version is no update.
result=$(run update-check 30)
if echo "$result" | grep -q 'version: "99.0.0"' && echo "$result" | grep -q "newCommitCount: 2"; then pass "update check finds version 99.0.0 with 2 commits"; else fail "update check" "$result"; fi
current_version=$("$ROOT/build/Bugbear.app/Contents/MacOS/Bugbear" --version)
printf 'WhatsNewRelease(id: 1, version: "%s", title: "Same", items: [])\n' "$current_version" > "$FEED_DIR/catalog.swift"
result=$(run update-check 30)
if echo "$result" | grep -q "upToDate"; then pass "same version $current_version is not an update"; else fail "same version is not an update" "$result"; fi
plist_version=$(defaults read "$ROOT/build/Bugbear.app/Contents/Info" CFBundleShortVersionString)
if [ "$plist_version" = "$current_version" ]; then pass "app version $plist_version comes from the release notes"; else fail "app version" "plist=$plist_version catalog=$current_version"; fi
kill "$FEED_PID" 2>/dev/null
defaults delete "$BUNDLE_ID" updateCompareURL 2>/dev/null
defaults delete "$BUNDLE_ID" updateCatalogURL 2>/dev/null
rm -rf "$FEED_DIR"

# 12. Errors in the log.
errors=$(grep -c "ERROR" "$LOG" || true)
if [ "$errors" = "0" ]; then pass "no errors in the log"; else fail "no errors in the log" "$errors errors"; grep "ERROR" "$LOG" | tail -5; fi

defaults write "$BUNDLE_ID" automationEnabled -bool false
echo
echo "$PASSES passed, $FAILURES failed. Log: $LOG"
[ "$FAILURES" = "0" ]
