#!/bin/bash
# End-to-end checks against the real app and real screen capture.
#
#   scripts/test/e2e.sh            build, launch, run every scenario, print PASS/FAIL
#
# Needs Screen Recording permission for Bugbear (granted once in System Settings).
# Turns on the local automation hook for the run and turns it off afterwards.
# The microphone and camera are skipped: they would show permission prompts.
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi
BUNDLE_ID="${BUGBEAR_BUNDLE_ID:-io.github.bugbear.app}"
# shellcheck disable=SC1091
source "$ROOT/scripts/test/lib/test-app.sh"
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
    scripts/dev/bugbear-command.sh "$command"
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
# Quit the person's Bugbear and keep a copy of their settings before any test setting is written.
quit_running_bugbear
defaults write "$BUNDLE_ID" automationEnabled -bool true
# Editor choices made by the tests go to a store of their own (EditorMemory); start it empty.
defaults delete "$BUNDLE_ID.tests" 2>/dev/null
defaults write "$BUNDLE_ID" recordSystemAudio -bool false
defaults write "$BUNDLE_ID" recordMicrophone -bool false
defaults write "$BUNDLE_ID" bufferMinutes -int 3
defaults write "$BUNDLE_ID" startBufferOnLaunch -bool true
# Update checks go to a local file server instead of GitHub.
FEED_DIR="$ROOT/build/e2e-update-feed"
mkdir -p "$FEED_DIR"
printf '{"status":"ahead","ahead_by":2,"commits":[{"sha":"1111111aaaa","commit":{"message":"Second change"}},{"sha":"2222222bbbb","commit":{"message":"Merge pull request #5 from someone/crop\\n\\nBetter crop"}}]}' > "$FEED_DIR/compare.json"
printf 'WhatsNewRelease(id: 99, version: "99.0.0", title: "Future", items: [])\n' > "$FEED_DIR/catalog.swift"
python3 -m http.server 8765 --bind 127.0.0.1 --directory "$FEED_DIR" >/dev/null 2>&1 &
FEED_PID=$!
defaults write "$BUNDLE_ID" updateCompareURL "http://127.0.0.1:8765/compare.json"
defaults write "$BUNDLE_ID" updateCatalogURL "http://127.0.0.1:8765/catalog.swift"
rm -f "$LOG"
open "$TEST_APP"
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
# A real drag on the screen leaves a mark that shows: the flags above were true while nothing drew.
live=$(run live-state)
lx=$(field "$live" x); ly=$(field "$live" y); lw=$(field "$live" w); lh=$(field "$live" h)
cx=$((lx + lw / 2)); cy=$((ly + lh / 2))
before_coral=$(field "$(run "screen-color:$((cx - 170)),$((cy - 110)),340,220")" coral)
run "post-drag:$((cx - 150)),$((cy - 90)):$((cx + 150)),$((cy + 90))" >/dev/null
sleep 0.6
live_after=$(run live-state)
after_coral=$(field "$(run "screen-color:$((cx - 170)),$((cy - 110)),340,220")" coral)
echo "      $live → marks=$(field "$live_after" marks) coral $before_coral → $after_coral"
if [ "$(field "$live_after" marks)" -ge 1 ] 2>/dev/null; then pass "a drag while drawing adds a mark"; else fail "a drag while drawing adds a mark" "$live_after"; fi
if [ "${after_coral:-0}" -gt $(( ${before_coral:-0} + 200 )) ] 2>/dev/null; then pass "the mark drawn during recording shows on the screen"; else fail "the mark drawn during recording shows on the screen" "coral $before_coral → $after_coral"; fi
# With two displays, drawing goes where the pointer is, not only on the recorded display.
other=$(run screen-center:1)
if [ "$(field "$other" count)" -gt 1 ] 2>/dev/null; then
    ox=$(field "$other" x); oy=$(field "$other" y)
    run draw-toggle >/dev/null
    run "post-move:$ox,$oy" >/dev/null
    run draw-toggle >/dev/null
    moved=$(run live-state)
    mx=$(field "$moved" x); my=$(field "$moved" y); mw=$(field "$moved" w); mh=$(field "$moved" h)
    run "post-drag:$((ox - 150)),$((oy - 90)):$((ox + 150)),$((oy + 90))" >/dev/null
    sleep 0.6
    other_coral=$(field "$(run "screen-color:$((ox - 170)),$((oy - 110)),340,220")" coral)
    if [ "$ox" -ge "$mx" ] && [ "$ox" -le $((mx + mw)) ] && [ "$oy" -ge "$my" ] && [ "$oy" -le $((my + mh)) ] && [ "${other_coral:-0}" -gt 200 ] 2>/dev/null; then pass "drawing on the other display shows there"; else fail "drawing on the other display" "$moved coral=$other_coral at $ox,$oy"; fi
fi
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
now_seconds() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }
marked_at=$(now_seconds)
run mark >/dev/null
sleep 25
saved_at=$(now_seconds)
result=$(run save:5 90)
echo "      $result"
file=$(file_of "$result")
if [ -n "$file" ] && [ -f "$file" ]; then
    duration=$(media_duration "$file")
    # The clip goes back to 5 s before the marker. The app logs how far back the marker was when the
    # save started; that has to match the test's own clock, and the clip has to match that.
    marker_ago=$(grep "save reaches back to a marker" "$LOG" | tail -1 | sed 's/.*marker \([0-9.]*\)s ago.*/\1/')
    measured_ago=$(echo "$saved_at - $marked_at" | bc)
    expected=$(echo "${marker_ago:-0} + 5" | bc)
    if [ -n "$marker_ago" ] && near "$marker_ago" "$measured_ago" 1.5 && near "$duration" "$expected" 0.6; then pass "save after ⌥⇧M reaches back to the marker (${duration}s, marker ${marker_ago}s ago)"; else fail "save after a marker" "got $duration, expected $expected (marker ${marker_ago:-not logged}s ago, the test measured ${measured_ago}s)"; fi
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
    capture_id="${saved##*→ }"
    capture_folder=$(find "$HOME/Library/Application Support/Bugbear" -type d -name "$capture_id" 2>/dev/null | head -1)
    duration=$(media_duration "$capture_folder/original.mp4")
    if at_least "${duration:-0}" 30; then pass "crash saves the time before it (${duration}s clip)"; else fail "crash clip length" "got $duration"; fi
    if [ -f "$capture_folder/crash-report.ips" ]; then pass "crash report kept next to the clip"; else fail "crash report kept next to the clip" "$capture_folder"; fi
    # The crash clip's editor opens its crash report and system log (recorded, not opened). The
    # system log is written a few seconds after the clip; wait for it so both buttons are there.
    for _ in $(seq 1 20); do
        if [ -f "$capture_folder/system.log" ]; then break; fi
        sleep 0.5
    done
    run system-actions:start >/dev/null
    run "open-capture:$capture_id" >/dev/null
    run "press:video:Crash report" >/dev/null
    run "press:video:System log" >/dev/null
    opened=$(run system-actions:read)
    run system-actions:stop >/dev/null
    run close-windows >/dev/null
    if [[ "$opened" == *"crash-report.ips"* ]] && { [ ! -f "$capture_folder/system.log" ] || [[ "$opened" == *"system.log"* ]]; }; then
        if [ -f "$capture_folder/system.log" ]; then pass "the crash clip's \"Crash report\" and \"System log\" buttons open them"; else pass "the crash clip's \"Crash report\" button opens it (no system log was saved)"; fi
    else fail "crash clip buttons" "$opened"; fi
else
    fail "crash detected and saved" "no 'crash clip saved' in the log"
fi
rm -rf "$crash_folder"

# 10. The system log collector ran for the saved clips.
if grep -q "system log for .*: [0-9]* lines" "$LOG"; then pass "system log collected ($(grep "system log for" "$LOG" | tail -1 | sed 's/.*system log for //'))"; else fail "system log collected" "no 'system log for' line"; fi

# 11. Update check finds a newer release and lists its commits; the same version is no update.
result=$(run update-check 30)
if echo "$result" | grep -q 'version: "99.0.0"' && echo "$result" | grep -q "newCommitCount: 2"; then pass "update check finds version 99.0.0 with 2 commits"; else fail "update check" "$result"; fi
if echo "$result" | grep -q 'title: "Better crop"' && echo "$result" | grep -q "pullRequest: Optional(5)" && echo "$result" | grep -q "changeCount: 1"; then pass "update lists the merged pull request by its title"; else fail "update pull request" "$result"; fi
current_version=$("$TEST_APP/Contents/MacOS/Bugbear" --version)
printf 'WhatsNewRelease(id: 1, version: "%s", title: "Same", items: [])\n' "$current_version" > "$FEED_DIR/catalog.swift"
result=$(run update-check 30)
if echo "$result" | grep -q "upToDate"; then pass "same version $current_version is not an update"; else fail "same version is not an update" "$result"; fi
plist_version=$(defaults read "$TEST_APP/Contents/Info" CFBundleShortVersionString)
if [ "$plist_version" = "$current_version" ]; then pass "app version $plist_version comes from the release notes"; else fail "app version" "plist=$plist_version catalog=$current_version"; fi
kill "$FEED_PID" 2>/dev/null
defaults delete "$BUNDLE_ID" updateCompareURL 2>/dev/null
defaults delete "$BUNDLE_ID" updateCatalogURL 2>/dev/null
rm -rf "$FEED_DIR"

# 11b. Copy text from the screen (⌥⇧O, after the area is picked): the text goes to the clipboard
# and a message says it can be pasted.
result=$(run "copy-text-file:$ROOT/docs/images/settings.png" 60)
if echo "$result" | grep -q "toast=true" && echo "$result" | grep -q "copied=.*[A-Za-z]"; then pass "copy text: clipboard and a 'paste with ⌘V' message"; else fail "copy text" "$result"; fi

# 11c. The buffer comes back by itself after the displays go away (issue #17). It used to try
# once after 2 s, find no display and stay on "Buffer error" with the displays back.
NO_DISPLAY_ERROR="startBuffer failed: No display available for capture"
no_display_errors() { grep -c "$NO_DISPLAY_ERROR" "$LOG" || true; }
back_lines() { grep -c "buffer is back after" "$LOG" || true; }
# Waits up to about $2 seconds for at least $1 "no display" failures in the log.
wait_for_no_display_errors() {
    local waited=0
    while [ "$waited" -lt "$2" ]; do
        if [ "$(no_display_errors)" -ge "$1" ]; then return 0; fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}
# Polls the status about $1 times (each poll takes a second or two).
wait_for_running() {
    local polls=0
    while [ "$polls" -lt "$1" ]; do
        if run status 10 | grep -q "^running"; then return 0; fi
        sleep 1
        polls=$((polls + 1))
    done
    return 1
}
errors_before=$(no_display_errors)
back_before=$(back_lines)
result=$(run buffer-lose:1 10)
if echo "$result" | grep -q "waiting=true"; then pass "a lost buffer waits to come back"; else fail "a lost buffer waits to come back" "$result"; fi
# Tries at 2 s (no display) and 5 s after it (starts).
if wait_for_running 20; then pass "the buffer starts again after a try that found no display"; else fail "the buffer starts again after a failed try" "$(run status 10)"; fi
# Two tries fail (2 s and 5 s); the next one is 15 s away, so waking up must start it at once.
run buffer-lose:2 10 >/dev/null
if wait_for_no_display_errors $((errors_before + 3)) 20; then
    run screens-woke 10 >/dev/null
    if wait_for_running 3; then pass "waking up starts a waiting buffer at once"; else fail "waking up starts a waiting buffer at once" "$(run status 10)"; fi
else
    fail "two tries found no display" "$(no_display_errors) errors"
fi
if [ "$(back_lines)" = "$((back_before + 2))" ]; then pass "the log says the buffer is back, both times"; else fail "the log says the buffer is back" "$(back_lines) lines"; fi
if [ "$(no_display_errors)" = "$((errors_before + 3))" ]; then pass "three tries found no display"; else fail "three tries found no display" "$(no_display_errors)"; fi

# 12. Errors in the log (the tries in 11c that found no display are expected).
errors=$(grep "ERROR" "$LOG" | grep -vc "$NO_DISPLAY_ERROR" || true)
if [ "$errors" = "0" ]; then pass "no errors in the log"; else fail "no errors in the log" "$errors errors"; grep "ERROR" "$LOG" | tail -5; fi

defaults write "$BUNDLE_ID" automationEnabled -bool false
echo
echo "$PASSES passed, $FAILURES failed. Log: $LOG"
[ "$FAILURES" = "0" ]
