#!/bin/bash
# Real-screen checks of the features that need other apps and the mouse: scrolling screenshot of a
# browser page, window resizing, ruler, color picker, design overlay, area recording through the
# picker, shortcuts, reports, step guide, comparison, editor sizes.
#
#   scripts/test/e2e-features.sh                     # in Google Chrome
#   E2E_BROWSER=Safari scripts/test/e2e-features.sh  # or another browser
#
# Opens a local test page in a new browser window and moves the mouse; don't touch the Mac while it runs (~2 min).
# Needs Screen Recording and Accessibility for the app. Restores the settings it changes.
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
R=scripts/dev/app-run.sh
BROWSER="${E2E_BROWSER:-Google Chrome}"
WORK="$ROOT/build/e2e-features"
FAILURES=0
PASSES=0

pass() { echo "PASS  $1"; PASSES=$((PASSES + 1)); }
fail() { echo "FAIL  $1 ${2:-}"; FAILURES=$((FAILURES + 1)); }
field() { echo "$1" | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }
# shellcheck disable=SC1091
source "$ROOT/scripts/test/lib/e2e-helpers.sh"

section "build and launch"
build_test_app || exit 1
# Quit the person's copy of the app and keep a copy of their settings before any test setting is written.
quit_running_app
rm -rf "$WORK"
mkdir -p "$WORK"
defaults write "$BUNDLE_ID" automationEnabled -bool true
# What the tests leave behind is cleaned up at the end: the captures they made (folders that were
# not there before) and the text on the clipboard.
CAPTURES_DIR="$HOME/Library/Application Support/$APP_NAME/Captures"
ls "$CAPTURES_DIR" 2>/dev/null | sort > "$WORK/captures-before.txt"
# Editor choices made by the tests go to a store of their own (EditorMemory); start it empty.
defaults delete "$BUNDLE_ID.tests" 2>/dev/null
pbpaste > "$WORK/clipboard-before.txt" 2>/dev/null
# The person's editor palette; the tests pick colors in a store of their own.
defaults read "$BUNDLE_ID" recentAnnotationColors > "$WORK/palette-before.txt" 2>/dev/null

section "a new install shows the welcome guide"
# Settings outlive a deleted app, so installing where no copy is starts the guide again;
# installing over a copy (an update) keeps them.
# The test copy shares the installed app's settings: keep what these steps touch and put it back.
saved_onboarding=$(defaults read "$BUNDLE_ID" onboardingCompleted 2>/dev/null || echo "")
saved_onboarding_page=$(defaults read "$BUNDLE_ID" onboardingPage 2>/dev/null || echo "")
saved_whats_new=$(defaults read "$BUNDLE_ID" whatsNewLastSeenID 2>/dev/null || echo "")
install_dir="$WORK/apps"
defaults write "$BUNDLE_ID" onboardingCompleted -bool true
APP_INSTALL_DIR="$install_dir" APP_NO_OPEN=1 scripts/build-app.sh --install-only >/dev/null 2>&1
if ! defaults read "$BUNDLE_ID" onboardingCompleted >/dev/null 2>&1; then pass "installing where no copy is forgets the finished guide"; else fail "a new install forgets the finished guide"; fi
defaults write "$BUNDLE_ID" onboardingCompleted -bool true
APP_INSTALL_DIR="$install_dir" APP_NO_OPEN=1 scripts/build-app.sh --install-only >/dev/null 2>&1
if [ "$(defaults read "$BUNDLE_ID" onboardingCompleted 2>/dev/null)" = "1" ]; then pass "installing over a copy (an update) keeps the finished guide"; else fail "an update keeps the finished guide"; fi
rm -rf "$install_dir"
defaults delete "$BUNDLE_ID" onboardingCompleted 2>/dev/null
defaults write "$BUNDLE_ID" automationFirstLaunch -bool true
open "$TEST_APP"
wait_for_value 15 "visible=true" $R window-visible:onboarding 10
result=$($R window-visible:onboarding 10)
if [ "$result" = "visible=true" ]; then pass "the first launch opens the welcome guide"; else fail "the first launch opens the welcome guide" "$result"; fi
pkill -x "$APP_NAME" 2>/dev/null
wait_for_app_to_quit
defaults delete "$BUNDLE_ID" automationFirstLaunch 2>/dev/null
if [ "$saved_onboarding" = "1" ]; then
    defaults write "$BUNDLE_ID" onboardingCompleted -bool true
else
    defaults delete "$BUNDLE_ID" onboardingCompleted 2>/dev/null
fi
if [ -n "$saved_onboarding_page" ]; then
    defaults write "$BUNDLE_ID" onboardingPage -int "$saved_onboarding_page"
fi
if [ -n "$saved_whats_new" ]; then
    defaults write "$BUNDLE_ID" whatsNewLastSeenID -int "$saved_whats_new"
else
    defaults delete "$BUNDLE_ID" whatsNewLastSeenID 2>/dev/null
fi

defaults delete "$BUNDLE_ID" feedbackLastCrashCheck 2>/dev/null
open "$TEST_APP"
wait_for 20 status_starts running
wait_for 10 defaults read "$BUNDLE_ID" feedbackLastCrashCheck
$R setting:readBrowserURL:false 10 >/dev/null
# The launch looks for a crash of the last run (no window in test runs) and remembers when it looked.
if defaults read "$BUNDLE_ID" feedbackLastCrashCheck >/dev/null 2>&1; then pass "launch checks for a crash of the last run"; else fail "launch checks for a crash of the last run" "feedbackLastCrashCheck not set"; fi
# The same command sent twice at once: each call has its own token, so each gets its own result file.
$R status 10 > "$WORK/status-first.txt" &
first_pid=$!
$R status 10 > "$WORK/status-second.txt" &
second_pid=$!
wait "$first_pid" "$second_pid"
if grep -q "captures=" "$WORK/status-first.txt" && grep -q "captures=" "$WORK/status-second.txt"; then pass "the same command sent twice gets two results"; else fail "the same command sent twice gets two results" "$(cat "$WORK/status-first.txt") / $(cat "$WORK/status-second.txt")"; fi
if [ "$($R ax 10)" = "trusted=true" ]; then pass "Accessibility is allowed"; else fail "Accessibility is allowed" "grant it in System Settings"; fi

# A long page with a sticky header and footer and 150 numbered rows.
python3 - "$WORK/long.html" <<'EOF'
import sys
rows = []
for i in range(1, 151):
    status = ["PAID", "FAILED", "PENDING", "REFUNDED"][i % 4]
    rows.append(f'<div class="row r{i % 5}"><b>Row {i:03d}</b> · order A7-{4500 + i} · {status} · {"x" * (i % 23)}</div>')
style = ("body{margin:0;font:18px -apple-system,sans-serif;background:#fff;color:#111}"
         "header{position:sticky;top:0;background:#1c1d20;color:#fff;padding:14px 20px;font-weight:600}"
         "footer{position:sticky;bottom:0;background:#ff6b4a;color:#1a0b06;padding:12px 20px;font-weight:600}"
         ".row{padding:10px 20px;border-bottom:1px solid #ddd;height:22px}"
         ".r0{background:#fafafa}.r1{background:#f2f7ff}.r2{background:#fff8f0}.r3{background:#f4fff4}.r4{background:#fff}")
html = (f'<!doctype html><html><head><meta charset="utf-8"><title>Scroll test</title><style>{style}</style></head><body>'
        f'<header>Scroll test · sticky header</header>{"".join(rows)}<footer>Sticky footer · end of page</footer></body></html>')
open(sys.argv[1], "w").write(html)
EOF
# A new window, so the browser windows you have open are not moved or resized.
case "$BROWSER" in
    *Chrome*|*Chromium*|*Edge*|*Brave*)
        # Chromium browsers open the page in a new window of the usual profile; nothing is typed into
        # whatever browser window happened to be in front.
        open -na "$BROWSER" --args --new-window "file://$WORK/long.html"
        # Real time: the browser opens a new window and loads the test page.
        sleep 4
        $R "activate-app:$BROWSER" 10 >/dev/null
        wait_browser_front
        ;;
    *)
        $R "activate-app:$BROWSER" 10 >/dev/null
        wait_browser_front
        front=$($R screen 10 | sed -n 's/.*front=//p')
        if [ "$front" = "$BROWSER" ]; then
            $R post-key:45:cmd 10 >/dev/null
            # Real time: the browser takes the shortcut and focuses its address bar; nothing in the app shows it.
            sleep 1.5
            printf '%s' "file://$WORK/long.html" | pbcopy
            $R post-key:37:cmd 10 >/dev/null
            # Real time: keystrokes into the browser go one at a time; its address bar shows no state to poll.
            sleep 0.3
            $R post-key:9:cmd 10 >/dev/null
            # Real time: keystrokes into the browser go one at a time; its address bar shows no state to poll.
            sleep 0.3
            $R post-key:36:none 10 >/dev/null
            # Real time: the browser loads the page; the title loop below waits for it too.
            sleep 3
        else
            # Other browsers ignore --new-window; they open the page in a window of their own choice.
            open -a "$BROWSER" "file://$WORK/long.html"
            # Real time: the browser opens the page; the title loop below waits for it too.
            sleep 4
        fi
        ;;
esac
# Resizing, moving and scrolling act on the front window: only ever on the test page. A new window
# is "Untitled" until the page loads, so its title is given a moment.
title=""
for _ in $(seq 30); do
    title=$($R front-title 10 | sed -n 's/^title=//p')
    case "$title" in "Scroll test"*) break ;; esac
    # Poll step of the title loop.
    sleep 0.5
done
case "$title" in
    "Scroll test"*) ;;
    *)
        echo "STOP  the front window is \"$title\", not the test page, so windows are left alone."
        $R setting:readBrowserURL:true 10 >/dev/null
        defaults write "$BUNDLE_ID" automationEnabled -bool false
        exit 1
        ;;
esac

# Steps below resize the front window or press keys in it: each one checks it is still the test page.
stop_unless_test_page() {
    if ! $R front-title 10 | grep -q "^title=Scroll test"; then
        echo "STOP  the front window is no longer the test page, so windows are left alone."
        $R setting:readBrowserURL:true 10 >/dev/null
        $R browser-accessibility-off 10 >/dev/null
        defaults write "$BUNDLE_ID" automationEnabled -bool false
        exit 1
    fi
}

section "window size"
stop_unless_test_page
result=$($R resize-front:1280x720 10)
if echo "$result" | grep -q "app=$BROWSER size=1280x720"; then pass "resize $BROWSER to 1280×720"; else fail "resize $BROWSER" "$result"; fi
stop_unless_test_page
$R resize-front:1100x760 10 >/dev/null
# Real time: the browser window finishes resizing and re-lays the page out.
sleep 1

section "scrolling screenshot"
stop_unless_test_page
$R post-key:115:none 10 >/dev/null
# Real time: the browser scrolls to the top (an animation); the page has no state to poll.
sleep 1
# The page area from Accessibility: normalized on its display, global frame, display width.
# Chrome builds its accessibility tree for a page on the first requests, so ask a few times.
web=""
for _ in 1 2 3 4 5; do
    web=$($R web-area 10)
    if [ "$web" != "no web area" ] && [ -n "$web" ]; then
        break
    fi
    # Poll step: the browser builds its accessibility tree on the first requests.
    sleep 1
done
normalized=$(echo "$web" | cut -d' ' -f1)
global=$(echo "$web" | cut -d' ' -f2)
screen_width=$(echo "$web" | cut -d' ' -f3)
# Minus 24 pt on the right for the scroll bar.
area=$(echo "$normalized" | awk -F, -v width="$screen_width" '{ printf "%.4f,%.4f,%.4f,%.4f", $1, $2, $3 - 24 / width, $4 }')
# The capture picks the display under the pointer: put it in the middle of the page.
page_center=$(echo "$global" | awk -F, '{ printf "%d,%d", $1 + $3 / 2, $2 + $4 / 2 }')
$R "move-pointer:$page_center" 10 >/dev/null
result=$($R "scroll-capture:$area" 300)
file=$(echo "$result" | sed -n 's/.*file=//p')
height=$(field "$result" height)
if [ -n "$file" ] && [ "${height:-0}" -gt 5000 ]; then pass "long screenshot ${height}px"; else fail "long screenshot" "$result"; fi
if [ -n "$file" ]; then
    $R "ocr-file:$file" 300 | sed 's/||/\n/g; s/|/\n/g' > "$WORK/ocr.txt"
    verdict=$(python3 - "$WORK/ocr.txt" <<'EOF'
import re, sys
text = open(sys.argv[1]).read()
raw = [int(number) for number in re.findall(r"Row (\d{3})", text)]
rows = []
for number in raw:
    if number in rows[-8:]:
        continue  # repeated where OCR pieces overlap
    rows.append(number)
missing = [number for number in range(1, 151) if number not in rows]
backwards = [pair for pair in zip(rows, rows[1:]) if pair[1] < pair[0]]
headers = len(re.findall(r"sticky header", text, re.I))
footers = len(re.findall(r"sticky footer", text, re.I))
print(f"missing={len(missing)} backwards={len(backwards)} headers={headers} footers={footers}")
EOF
)
    if [ "$verdict" = "missing=0 backwards=0 headers=1 footers=1" ]; then pass "all 150 rows once, in order, header and footer once"; else fail "long screenshot content" "$verdict"; fi
fi

section "color picker"
( $R pick-color-test 30 > "$WORK/pick.txt" ) &
# Real time: the color picker command runs in the background and has to start before the next step.
sleep 2
# The middle of the sticky footer: 20 pt above the bottom of the page area.
if [ -n "$global" ] && echo "$global" | grep -q ","; then
    footer_point=$(echo "$global" | awk -F, '{ printf "%d,%d", $1 + $3 / 2, $2 + $4 - 20 }')
    $R "post-click:$footer_point" 10 >/dev/null
    wait
    if grep -q "hex=#FF6B4A" "$WORK/pick.txt"; then pass "picks #FF6B4A from the footer"; else fail "color picker" "$(cat "$WORK/pick.txt")"; fi
else
    # Without the page area there is no safe point to click: cancel the picker instead.
    $R post-key:53:none 10 >/dev/null
    wait
    fail "color picker" "the page area was not found"
fi

section "ruler"
$R ruler-start 10 >/dev/null
$R post-drag:400,300:700,500 10 >/dev/null
$R "activate-app:$BROWSER" 10 >/dev/null
wait_browser_front
# Real time: the window becomes key a moment after the app is in front.
sleep 0.5
stop_unless_test_page
$R post-key:53:none 10 >/dev/null
wait_for_value 10 "active=false" $R ruler-state 10
if [ "$($R ruler-state 10)" = "active=false" ]; then pass "Esc closes the ruler even with $BROWSER in front"; else fail "ruler Esc"; $R ruler-stop 10 >/dev/null; fi

section "design overlay"
result=$($R overlay-test:2 20)
if echo "$result" | grep -q "frame=700x400 alpha=0.40"; then pass "1400 px design at @2x is 700×400 pt"; else fail "overlay size" "$result"; fi
result=$($R overlay-click-through:true 10)
if echo "$result" | grep -q "clickThrough=true"; then pass "overlay click-through"; else fail "overlay click-through" "$result"; fi
$R overlay-close 10 >/dev/null

section "area recording through the picker"
$R "activate-app:$BROWSER" 10 >/dev/null
wait_browser_front
# Real time: the window becomes key a moment after the app is in front.
sleep 0.5
$R record-area-picker 10 >/dev/null
wait_for_text 10 region-picker windows_now
chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
$R "post-click:$chip" 10 >/dev/null
wait_for 10 picker_selected
$R post-key:36:none 10 >/dev/null
wait_for_text 15 "recording=true" $R recording-region 10
result=$($R recording-region 10)
# One outline window per display: a frame on this one, "Not recorded" on the others.
screen_count=$($R screens 10 | tr ';' '\n' | wc -l | tr -d ' ')
if echo "$result" | grep -q "region=640x360 recording=true outline=$screen_count"; then pass "720p chip picks 640×360 pt and shows the outline on $screen_count display(s)"; else fail "area picker" "$result"; fi
# Real time: the recording runs a bit so the clip has frames to compare.
sleep 2
$R record-stop 60 >/dev/null
result=$($R "frame-of-latest:1:$WORK/area-frame.png" 30)
if [ "$result" = "frame=1280x720" ]; then pass "area clip is 1280×720"; else fail "area clip size" "$result"; fi
$R close-windows 10 >/dev/null

section "resizing the area while recording"
# The frame has handles: dragging the bottom-right one makes the area bigger, and the clip gets
# the area as it is when the recording stops.
$R "activate-app:$BROWSER" 10 >/dev/null
wait_browser_front
# Real time: the window becomes key a moment after the app is in front.
sleep 0.5
$R record-area-picker 10 >/dev/null
wait_for_text 10 region-picker windows_now
chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
$R "post-click:$chip" 10 >/dev/null
wait_for 10 picker_selected
$R post-key:36:none 10 >/dev/null
wait_for_text 15 "recording=true" $R recording-region 10
handles=$($R area-handles 10)
handle_count=$(echo "$handles" | tr ';' '\n' | grep -c ",")
corner=$(echo "$handles" | cut -d';' -f2)
corner_x=${corner%,*}
corner_y=${corner#*,}
if [ "$handle_count" = "8" ]; then pass "the recording frame has 8 handles"; else fail "recording frame handles" "$handles"; fi
# The picker took the focus for Return; once the recording runs, the browser is in front again.
front_before=$($R front-app 10)
if [ "$front_before" = "$BROWSER" ]; then pass "after picking the area $BROWSER is in front again"; else fail "the area picker kept the focus" "$front_before"; fi
$R "post-drag:$corner_x,$corner_y:$((corner_x + 100)),$((corner_y + 50))" 15 >/dev/null
wait_for_text 10 "region=740x410 recording=true" $R recording-region 10
result=$($R recording-region 10)
if echo "$result" | grep -q "region=740x410 recording=true"; then pass "dragging the corner while recording makes the area 740×410 pt"; else fail "resize the area while recording" "$result"; fi
moved=$($R area-handles 10 | cut -d';' -f2)
if [ "$moved" = "$((corner_x + 100)),$((corner_y + 50))" ]; then pass "the handle follows the frame"; else fail "the handle follows the frame" "$moved, expected $((corner_x + 100)),$((corner_y + 50))"; fi
front=$($R front-app 10)
if [ "$front_before" = "$BROWSER" ] && [ "$front" = "$BROWSER" ]; then pass "dragging a handle leaves $BROWSER in front"; else fail "dragging a handle took the focus" "before=$front_before after=$front"; fi
# Real time: the recording runs a bit so the clip has frames to compare.
sleep 2
$R record-stop 60 >/dev/null
result=$($R "frame-of-latest:1:$WORK/area-resized.png" 30)
if [ "$result" = "frame=1480x820" ]; then pass "the clip has the resized area, 1480×820"; else fail "resized area clip size" "$result"; fi
if [ -z "$($R area-handles 10)" ]; then pass "the handles go when the recording stops"; else fail "the handles go when the recording stops"; fi
$R close-windows 10 >/dev/null

section "moving the area"
# In the picker a drag inside the area or by its grip moves it and an edge handle moves one side; while recording,
# the grip above the frame moves the whole area without resizing it, and the clip gets that place.
$R "activate-app:$BROWSER" 10 >/dev/null
wait_browser_front
# Real time: the window becomes key a moment after the app is in front.
sleep 0.5
$R record-area-picker 10 >/dev/null
wait_for_text 10 region-picker windows_now
chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
$R "post-click:$chip" 10 >/dev/null
wait_for 10 picker_selected
picked=$($R picker-selection 10)
IFS=, read -r pick_x pick_y pick_width pick_height <<< "$picked"
$R "post-drag:$((pick_x + pick_width / 2)),$((pick_y + pick_height / 2)):$((pick_x + pick_width / 2 + 100)),$((pick_y + pick_height / 2 + 60))" 15 >/dev/null
wait_for_value 10 "$((pick_x + 100)),$((pick_y + 60)),$pick_width,$pick_height" $R picker-selection 10
result=$($R picker-selection 10)
if [ "$result" = "$((pick_x + 100)),$((pick_y + 60)),$pick_width,$pick_height" ]; then pass "dragging inside the picked area moves it by 100,60 pt and keeps its size"; else fail "move the area in the picker" "$picked -> $result"; fi
pick_x=$((pick_x + 100))
pick_y=$((pick_y + 60))
$R "post-drag:$((pick_x + pick_width)),$((pick_y + pick_height / 2)):$((pick_x + pick_width + 80)),$((pick_y + pick_height / 2 + 40))" 15 >/dev/null
wait_for_value 10 "$pick_x,$pick_y,$((pick_width + 80)),$pick_height" $R picker-selection 10
result=$($R picker-selection 10)
if [ "$result" = "$pick_x,$pick_y,$((pick_width + 80)),$pick_height" ]; then pass "the right edge handle in the picker makes the area 80 pt wider and nothing else"; else fail "edge handle in the picker" "$result"; fi
pick_width=$((pick_width + 80))
grip=$($R picker-grip 10)
grip_x=${grip%,*}
grip_y=${grip#*,}
result="no grip"
if [ -n "$grip" ]; then
    $R "post-drag:$grip_x,$grip_y:$((grip_x - 60)),$((grip_y + 40))" 15 >/dev/null
    wait_for_value 10 "$((pick_x - 60)),$((pick_y + 40)),$pick_width,$pick_height" $R picker-selection 10
    result=$($R picker-selection 10)
fi
if [ "$result" = "$((pick_x - 60)),$((pick_y + 40)),$pick_width,$pick_height" ]; then pass "the grip above the picked area moves it by -60,40 pt and keeps its size"; else fail "grip in the picker" "$grip: $result"; fi
pick_x=$((pick_x - 60))
pick_y=$((pick_y + 40))
$R post-key:36:none 10 >/dev/null
wait_for_text 15 "recording=true" $R recording-region 10
result=$($R recording-region 10)
if echo "$result" | grep -q "region=${pick_width}x${pick_height} recording=true .* at=$pick_x,$pick_y$"; then pass "the recording takes the moved and widened area"; else fail "area from the picker" "$result, expected ${pick_width}x${pick_height} at $pick_x,$pick_y"; fi
grip=$($R area-grip 10)
grip_x=${grip%,*}
grip_y=${grip#*,}
$R "post-drag:$grip_x,$grip_y:$((grip_x - 120)),$((grip_y + 50))" 15 >/dev/null
wait_for_text 10 "at=$((pick_x - 120)),$((pick_y + 50))" $R recording-region 10
result=$($R recording-region 10)
if echo "$result" | grep -q "region=${pick_width}x${pick_height} recording=true .* at=$((pick_x - 120)),$((pick_y + 50))$"; then pass "dragging the grip while recording moves the area by -120,50 pt and keeps its size"; else fail "move the area while recording" "$result, expected at $((pick_x - 120)),$((pick_y + 50))"; fi
result=$($R area-grip 10)
if [ "$result" = "$((grip_x - 120)),$((grip_y + 50))" ]; then pass "the grip follows the frame"; else fail "the grip follows the frame" "$result"; fi
front=$($R front-app 10)
if [ "$front" = "$BROWSER" ]; then pass "dragging the grip leaves $BROWSER in front"; else fail "dragging the grip took the focus" "$front"; fi
# Real time: the recording runs a bit so the clip has frames to compare.
sleep 2
$R record-stop 60 >/dev/null
result=$($R "frame-of-latest:1:$WORK/area-moved.png" 30)
if [ "$result" = "frame=$((pick_width * 2))x$((pick_height * 2))" ]; then pass "the clip of the moved area is $((pick_width * 2))×$((pick_height * 2))"; else fail "moved area clip size" "$result"; fi
if [ -z "$($R area-grip 10)" ]; then pass "the grip goes when the recording stops"; else fail "the grip goes when the recording stops"; fi
$R close-windows 10 >/dev/null

section "an area across displays"
# With two displays the area can be picked across them, or moved onto the seam while recording; the
# clip has both displays in their places (no half left black) at the sharper display's density.
across_screens=$($R screens 10 | tr ';' '\n' | grep -c ':')
if [ "$across_screens" -lt 2 ]; then
    echo "  (one display: skipped)"
else
    # Where the area goes: its middle on the seam between the picker's first screen and a screen
    # beside it (or above or below), halfway along the part of the seam both share. Top-left screen
    # points. The clip's density is the sharper of the two screens'.
    seam_target() {
        local screens home candidate
        screens=$($R picker-screens 10 | tr ';' '\n')
        home=$(echo "$screens" | head -1)
        IFS=, read -r home_x home_y home_width home_height <<< "${home%@*}"
        seam_axis=""
        for candidate in $(echo "$screens" | tail -n +2); do
            IFS=, read -r other_x other_y other_width other_height <<< "${candidate%@*}"
            if [ "$other_x" = $((home_x + home_width)) ] || [ $((other_x + other_width)) = "$home_x" ]; then
                seam_axis=x
                seam_x=$other_x
                if [ "$other_x" -lt "$home_x" ]; then seam_x=$home_x; fi
                low=$home_y; if [ "$other_y" -gt "$low" ]; then low=$other_y; fi
                high=$((home_y + home_height)); if [ $((other_y + other_height)) -lt "$high" ]; then high=$((other_y + other_height)); fi
                target_x=$seam_x
                target_y=$(((low + high) / 2))
            elif [ "$other_y" = $((home_y + home_height)) ] || [ $((other_y + other_height)) = "$home_y" ]; then
                seam_axis=y
                seam_y=$other_y
                if [ "$other_y" -lt "$home_y" ]; then seam_y=$home_y; fi
                low=$home_x; if [ "$other_x" -gt "$low" ]; then low=$other_x; fi
                high=$((home_x + home_width)); if [ $((other_x + other_width)) -lt "$high" ]; then high=$((other_x + other_width)); fi
                target_x=$(((low + high) / 2))
                target_y=$seam_y
            fi
            if [ -n "$seam_axis" ]; then
                clip_scale=${home#*@}
                if [ "${candidate#*@}" -gt "$clip_scale" ]; then clip_scale=${candidate#*@}; fi
                return 0
            fi
        done
        return 1
    }
    # Both halves across the seam show a display: little pure black (the stitch's empty background).
    check_both_halves() {
        local halves first second
        halves=$($R "png-black:$1" 30)
        if [ "$seam_axis" = x ]; then
            first=$(echo "$halves" | sed -n 's/.*left=\([0-9]*\).*/\1/p')
            second=$(echo "$halves" | sed -n 's/.*right=\([0-9]*\).*/\1/p')
        else
            first=$(echo "$halves" | sed -n 's/.*top=\([0-9]*\).*/\1/p')
            second=$(echo "$halves" | sed -n 's/.*bottom=\([0-9]*\).*/\1/p')
        fi
        if [ -n "$first" ] && [ -n "$second" ] && [ "$first" -lt 50 ] && [ "$second" -lt 50 ]; then pass "$2: both displays are in the clip ($halves)"; else fail "$2: a display is missing from the clip" "$halves"; fi
    }

    # Displays that touch no other one (a gap between them) have no seam to cross.
    $R record-area-picker 10 >/dev/null
    wait_for_text 10 region-picker windows_now
    has_seam=0
    if seam_target; then has_seam=1; fi
    $R post-key:53:none 10 >/dev/null
    wait_for_no_text 10 region-picker windows_now
fi
if [ "$across_screens" -ge 2 ] && [ "$has_seam" = 0 ]; then
    echo "  (no display touches the one with the pointer: skipped)"
elif [ "$across_screens" -ge 2 ]; then
    $R "activate-app:$BROWSER" 10 >/dev/null
    wait_browser_front
    # Real time: the window becomes key a moment after the app is in front.
    sleep 0.5
    $R record-area-picker 10 >/dev/null
    wait_for_text 10 region-picker windows_now
    picker_count=$($R picker-screens 10 | tr ';' '\n' | grep -c ',')
    if [ "$picker_count" = "$across_screens" ]; then pass "the area picker covers all $across_screens displays"; else fail "picker on every display" "$picker_count of $across_screens"; fi
    chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
    $R "post-click:$chip" 10 >/dev/null
    wait_for 10 picker_selected
    IFS=, read -r pick_x pick_y pick_width pick_height <<< "$($R picker-selection 10)"
    seam_target
    grip=$($R picker-grip 10)
    result="no grip"
    if [ -n "$grip" ]; then
        dx=$((target_x - (pick_x + pick_width / 2)))
        dy=$((target_y - (pick_y + pick_height / 2)))
        $R "post-drag:${grip%,*},${grip#*,}:$((${grip%,*} + dx)),$((${grip#*,} + dy))" 15 >/dev/null
        wait_for_value 10 "$((target_x - pick_width / 2)),$((target_y - pick_height / 2)),$pick_width,$pick_height" $R picker-selection 10
        result=$($R picker-selection 10)
    fi
    expected="$((target_x - pick_width / 2)),$((target_y - pick_height / 2)),$pick_width,$pick_height"
    if [ "$result" = "$expected" ]; then pass "the picker's grip puts the area across the seam of two displays"; else fail "area across displays in the picker" "$result, expected $expected"; fi
    $R post-key:36:none 10 >/dev/null
    wait_for_text 15 "recording=true" $R recording-region 10
    result=$($R recording-region 10)
    if echo "$result" | grep -q "region=${pick_width}x${pick_height} recording=true .* at=$((target_x - pick_width / 2)),$((target_y - pick_height / 2))$"; then pass "the recording takes the area across displays"; else fail "recording an area across displays" "$result"; fi
    # Real time: the recording runs a bit so the clip has frames to compare.
    sleep 2
    $R record-stop 60 >/dev/null
    result=$($R "frame-of-latest:1:$WORK/area-across.png" 30)
    if [ "$result" = "frame=$((pick_width * clip_scale))x$((pick_height * clip_scale))" ]; then pass "the clip across displays is $((pick_width * clip_scale))×$((pick_height * clip_scale)), the sharper display's density"; else fail "clip across displays size" "$result"; fi
    check_both_halves "$WORK/area-across.png" "picked across the seam"
    $R close-windows 10 >/dev/null

    # The same while recording: the area starts on one display, its grip takes it onto the seam.
    $R "activate-app:$BROWSER" 10 >/dev/null
    wait_browser_front
    # Real time: the window becomes key a moment after the app is in front.
    sleep 0.5
    $R record-area-picker 10 >/dev/null
    wait_for_text 10 region-picker windows_now
    chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
    $R "post-click:$chip" 10 >/dev/null
    wait_for 10 picker_selected
    IFS=, read -r pick_x pick_y pick_width pick_height <<< "$($R picker-selection 10)"
    seam_target
    $R post-key:36:none 10 >/dev/null
    wait_for_text 15 "recording=true" $R recording-region 10
    grip=$($R area-grip 10)
    result="no grip"
    if [ -n "$grip" ]; then
        dx=$((target_x - (pick_x + pick_width / 2)))
        dy=$((target_y - (pick_y + pick_height / 2)))
        $R "post-drag:${grip%,*},${grip#*,}:$((${grip%,*} + dx)),$((${grip#*,} + dy))" 15 >/dev/null
        wait_for_text 10 "at=$((target_x - pick_width / 2)),$((target_y - pick_height / 2))" $R recording-region 10
        result=$($R recording-region 10)
    fi
    if echo "$result" | grep -q "region=${pick_width}x${pick_height} recording=true .* at=$((target_x - pick_width / 2)),$((target_y - pick_height / 2))$"; then pass "the recording frame's grip moves the area onto the seam of two displays"; else fail "moving the area across displays while recording" "$result"; fi
    # Real time: the recording runs a bit so the clip has frames to compare.
    sleep 2
    $R record-stop 60 >/dev/null
    result=$($R "frame-of-latest:1:$WORK/area-moved-across.png" 30)
    if [ "$result" = "frame=$((pick_width * clip_scale))x$((pick_height * clip_scale))" ]; then pass "the clip of the area moved across displays is $((pick_width * clip_scale))×$((pick_height * clip_scale))"; else fail "moved across displays clip size" "$result"; fi
    check_both_halves "$WORK/area-moved-across.png" "moved across the seam"
    $R close-windows 10 >/dev/null
fi

# Only the displays the area touches run at native resolution (and the recording frame rate); the
# others keep the buffer's. Moving the area onto another display takes that one to native resolution
# on the running stream, without a restart; moving it back changes nothing more.
if [ "$across_screens" -lt 2 ]; then
    echo "  (native resolution per display: skipped: one display)"
else
    screen_list=$($R screens 10 | tr ';' '\n')
    home_line=$(echo "$screen_list" | grep " pointer$" | head -1)
    if [ -z "$home_line" ]; then home_line=$(echo "$screen_list" | head -1); fi
    other_line=$(echo "$screen_list" | grep -v -F "$home_line" | head -1)
    primary_line=$(echo "$screen_list" | head -1)
    max_height=$(setting_value maxHeight)
    # display_sizes <screens line> <maxHeight>: "id native normal" in pixels, as ScreenBuffer works them out.
    display_sizes() {
        python3 - "$1" "$2" <<'PY'
import sys
line, max_height = sys.argv[1], int(sys.argv[2] or 0)
display, rest = line.split(":", 1)
rest = rest.replace(" pointer", "")
frame, scale = rest.split("@")
x, y, size = frame.split(",")
width, height = size.split("x")
native_width = float(width) * float(scale)
native_height = float(height) * float(scale)
normal_width, normal_height = native_width, native_height
if max_height > 0 and native_height > max_height:
    ratio = max_height / native_height
    normal_width = native_width * ratio
    normal_height = native_height * ratio
def even(value):
    return int(value / 2) * 2
print(f"{display} {even(native_width)}x{even(native_height)} {even(normal_width)}x{even(normal_height)}")
PY
    }
    read -r home_id home_native _ <<< "$(display_sizes "$home_line" "$max_height")"
    read -r other_id other_native other_normal <<< "$(display_sizes "$other_line" "$max_height")"
    # The other display's middle in top-left screen points (the main display's top is y 0).
    IFS=, read -r _ _ primary_size <<< "${primary_line#*:}"
    primary_height=${primary_size%%@*}
    primary_height=${primary_height#*x}
    IFS=, read -r other_x other_y other_size <<< "${other_line#*:}"
    other_size=${other_size%%@*}
    other_center_x=$((other_x + ${other_size%x*} / 2))
    other_center_y=$((primary_height - other_y - ${other_size#*x} / 2))

    $R "activate-app:$BROWSER" 10 >/dev/null
    wait_browser_front
    # Real time: the window becomes key a moment after the app is in front.
    sleep 0.5
    $R "record-area:0.2,0.2,0.3,0.3:$home_id" 20 >/dev/null
    # Both displays at the sizes the next check expects.
    sizes_show() { local shown; shown=";$($R buffer-sizes 10);"; [[ "$shown" == *";$1=$2;"* && "$shown" == *";$3=$4;"* ]]; }
    wait_for 15 sizes_show "$home_id" "$home_native" "$other_id" "$other_normal"
    sizes=$($R buffer-sizes 10)
    if echo ";$sizes;" | grep -q ";$home_id=$home_native;" && echo ";$sizes;" | grep -q ";$other_id=$other_normal;"; then pass "an area on one display: that display at native resolution ($home_native), the other one at the buffer's ($other_normal)"; else fail "native resolution only on the area's display" "$sizes, expected $home_id=$home_native $other_id=$other_normal"; fi
    started_before=$(grep -c "buffer\[.*\] started" "$LOG")
    region=$($R recording-region 10)
    region_size=$(echo "$region" | sed -n 's/.*region=\([0-9]*x[0-9]*\).*/\1/p')
    region_at=$(echo "$region" | sed -n 's/.* at=\([-0-9]*,[-0-9]*\)$/\1/p')
    area_center_x=$((${region_at%,*} + ${region_size%x*} / 2))
    area_center_y=$((${region_at#*,} + ${region_size#*x} / 2))
    dx=$((other_center_x - area_center_x))
    dy=$((other_center_y - area_center_y))
    grip=$($R area-grip 10)
    if [ -n "$grip" ]; then
        $R "post-drag:${grip%,*},${grip#*,}:$((${grip%,*} + dx)),$((${grip#*,} + dy))" 15 >/dev/null
    fi
    wait_for 15 sizes_show "$other_id" "$other_native" "$home_id" "$home_native"
    sizes=$($R buffer-sizes 10)
    started_moved=$(grep -c "buffer\[.*\] started" "$LOG")
    if echo ";$sizes;" | grep -q ";$other_id=$other_native;" && echo ";$sizes;" | grep -q ";$home_id=$home_native;"; then pass "the area moved onto the other display takes it to native resolution ($other_native), the first one stays"; else fail "native resolution after moving the area" "$sizes, expected $home_id=$home_native $other_id=$other_native"; fi
    if [ "$started_moved" = "$started_before" ]; then pass "moving the area changed the resolution without restarting a stream"; else echo "  (note: a stream restarted for native resolution: $started_before -> $started_moved started lines)"; fi
    grip=$($R area-grip 10)
    if [ -n "$grip" ]; then
        $R "post-drag:${grip%,*},${grip#*,}:$((${grip%,*} - dx)),$((${grip#*,} - dy))" 15 >/dev/null
    fi
    # Negative check: moving back must not restart a stream; a restart would show up in this time.
    sleep 2
    sizes_back=$($R buffer-sizes 10)
    started_back=$(grep -c "buffer\[.*\] started" "$LOG")
    if [ "$started_back" = "$started_moved" ] && [ "$sizes_back" = "$sizes" ]; then pass "moving the area back restarts nothing and changes no size"; else fail "moving the area back" "started $started_moved -> $started_back, sizes $sizes -> $sizes_back"; fi
    region=$($R recording-region 10)
    region_size=$(echo "$region" | sed -n 's/.*region=\([0-9]*x[0-9]*\).*/\1/p')
    home_scale=$(echo "$home_line" | sed -n 's/.*@\([0-9.]*\).*/\1/p')
    expected_frame=$(python3 -c "w, h = '$region_size'.split('x'); s = float('$home_scale'); print(f'frame={int(int(w) * s / 2) * 2}x{int(int(h) * s / 2) * 2}')")
    $R record-stop 60 >/dev/null
    result=$($R "frame-of-latest:1:$WORK/area-native-per-display.png" 30)
    if [ "$result" = "$expected_frame" ]; then pass "the clip of the area moved there and back is saved at the area's size (${expected_frame#frame=})"; else fail "clip after moving between displays" "$result, expected $expected_frame"; fi
    # Without "Keep all displays" the buffer leaves the other display out again.
    sizes=$($R buffer-sizes 10)
    if echo ";$sizes;" | grep -q ";$other_id=$other_normal;" || ! echo ";$sizes;" | grep -q ";$other_id="; then pass "after the recording the other display is back at the buffer's resolution"; else fail "buffer resolution after the recording" "$sizes, expected $other_id=$other_normal or not captured"; fi
    $R close-windows 10 >/dev/null

    # Stopped on the other display: its first seconds were recorded at the buffer's resolution, the
    # rest at native. The clip has the area where it ends for the whole time, so the frame at 1 s comes
    # from the smaller part and must be scaled up to fill the clip, not sit in a corner.
    $R "activate-app:$BROWSER" 10 >/dev/null
    wait_browser_front
    # Real time: the window becomes key a moment after the app is in front.
    sleep 0.5
    $R "record-area:0.2,0.2,0.3,0.3:$home_id" 20 >/dev/null
    wait_for_text 15 "recording=true" $R recording-region 10
    grip=$($R area-grip 10)
    if [ -n "$grip" ]; then
        $R "post-drag:${grip%,*},${grip#*,}:$((${grip%,*} + dx)),$((${grip#*,} + dy))" 15 >/dev/null
    fi
    # Real time: the stream changes to the native resolution of the new display; the buffer sizes read the same before and after.
    sleep 3
    region=$($R recording-region 10)
    region_size=$(echo "$region" | sed -n 's/.*region=\([0-9]*x[0-9]*\).*/\1/p')
    other_scale=$(echo "$other_line" | sed -n 's/.*@\([0-9.]*\).*/\1/p')
    expected_frame=$(python3 -c "w, h = '$region_size'.split('x'); s = float('$other_scale'); print(f'frame={int(int(w) * s / 2) * 2}x{int(int(h) * s / 2) * 2}')")
    $R record-stop 60 >/dev/null
    result=$($R "frame-of-latest:1:$WORK/area-native-later.png" 30)
    if [ "$result" = "$expected_frame" ]; then pass "the clip of the area stopped on the other display has its native density (${expected_frame#frame=})"; else fail "clip stopped on the other display" "$result, expected $expected_frame"; fi
    halves=$($R "png-black:$WORK/area-native-later.png" 30)
    right=$(echo "$halves" | sed -n 's/.*right=\([0-9]*\).*/\1/p')
    bottom=$(echo "$halves" | sed -n 's/.*bottom=\([0-9]*\).*/\1/p')
    if [ -n "$right" ] && [ -n "$bottom" ] && [ "$right" -lt 50 ] && [ "$bottom" -lt 50 ]; then pass "the part recorded before the move fills the clip ($halves)"; else fail "the part before the move is not scaled up" "$halves"; fi
    $R close-windows 10 >/dev/null
fi

section "area picker buttons"
# The picker draws its buttons by hand; VoiceOver and the tests press them by name.
$R record-area-picker 10 >/dev/null
wait_for_text 10 region-picker windows_now
$R controls:region-picker 30 | sed 's/ ;; /\n/g' | sed "s#^#region-picker|#" > "$WORK/picker-controls.txt"
size_result=$(press_in region-picker "Size 720p")
record_result=$(press_in region-picker Record)
wait_for_text 15 "recording=true" $R recording-region 10
result=$($R recording-region 10)
if [ "$size_result" = "pressed" ] && [ "$record_result" = "pressed" ] && echo "$result" | grep -q "region=640x360 recording=true"; then pass "area picker \"Size\" chips and \"Record\" pressed by name record that area"; else fail "area picker buttons" "$size_result $record_result $result"; fi
$R record-stop 60 >/dev/null
$R close-windows 10 >/dev/null

section "dock icon"
# The icon is in the Dock while a window is open. A click brings the window back; with no window
# left it opened nothing, so now the menu opens. macOS says where the app is:
# Foreground with a Dock icon, UIElement in the menu bar only.
dock_type() { lsappinfo info -only ApplicationType "$(pgrep -f "$TEST_APP/Contents/MacOS/$APP_NAME\$" | head -1)" 2>/dev/null | cut -d'"' -f4; }
$R close-windows 10 >/dev/null
$R open-space 30 >/dev/null
wait_for 10 window_open space
result=$($R dock-reopen 10)
in_dock=$(dock_type)
if [ "$(field "$result" windows)" = "1" ] && [ "$in_dock" = "Foreground" ] && [ "$(field "$result" menu)" = "false" ]; then pass "Dock icon click with a window open brings the window"; else fail "dock icon with a window" "$result $in_dock"; fi
$R close-windows 10 >/dev/null
# Real time: the window closes before the Dock icon is clicked (no state for "no windows").
sleep 0.5
result=$($R dock-reopen 10)
# Real time: macOS changes the Dock icon kind after the click; read from outside the app.
sleep 1.5
in_dock=$(dock_type)
# macOS 26 lets a process change its kind only once, so the icon may stay; a click on it then
# opens the menu, which is what has to work.
if [ "$(field "$result" windows)" = "0" ] && [ "$(field "$result" menu)" = "true" ]; then pass "Dock icon click with no window opens the menu ($in_dock)"; else fail "dock icon with no window" "$result $in_dock"; fi
$R close-panel 10 >/dev/null

section "shortcuts"
LOG="$HOME/Library/Logs/$APP_NAME/$APP_NAME.log"
before=$(grep -c "marker added" "$LOG")
$R post-key:46:option,shift 10 >/dev/null
wait_for 10 marker_count_above "$before"
if [ "$(grep -c "marker added" "$LOG")" -gt "$before" ]; then pass "⌥⇧M marks the moment"; else fail "⌥⇧M"; fi
$R hotkey-set:ruler:25:cmd,shift 10 >/dev/null
if $R hotkey-set:draw:19:option,shift 10 | grep -q "conflict with saveMinute"; then pass "a taken shortcut is refused"; else fail "shortcut conflict"; fi
$R post-key:25:cmd,shift 10 >/dev/null
wait_for_value 10 "active=true" $R ruler-state 10
if [ "$($R ruler-state 10)" = "active=true" ]; then pass "custom ⇧⌘9 opens the ruler"; else fail "custom shortcut"; fi
$R ruler-stop 10 >/dev/null
$R hotkey-reset 10 >/dev/null

section "reports, guide, comparison, editors"
$R "report-settings-save:$WORK/report-settings-1.json" 10 >/dev/null
$R fields:Stand=stage-3,Build=1.42 10 >/dev/null
$R screenshot-full 40 >/dev/null
$R close-windows 10 >/dev/null
if [ "$($R extras-latest 10)" = "extras=Stand=stage-3,Build=1.42" ]; then pass "report fields saved with the capture"; else fail "report fields"; fi
$R report:jira 10 >/dev/null
if pbpaste | grep -q "^\* \*Stand:\* stage-3"; then pass "Jira wiki report"; else fail "Jira wiki report"; fi
$R report:markdown 10 >/dev/null
# Straight to the steps: no Summary (the ticket has a title), no times, no local file paths.
first_line=$(pbpaste | head -1)
if [ "$first_line" = "## Steps to reproduce" ] && ! pbpaste | grep -qE "Summary|Attachments|^[0-9]+\. \["; then pass "Markdown report starts with the steps, without times or attachments"; else fail "Markdown report" "$(pbpaste | head -5)"; fi
$R "report-settings-restore:$WORK/report-settings-1.json" 10 >/dev/null
$R screenshot-full 40 >/dev/null
$R close-windows 10 >/dev/null
result=$($R "guide-latest:2:$WORK" 60)
if echo "$result" | grep -q "steps=2 .* pdf=true pages=2"; then pass "step guide PNG and PDF"; else fail "step guide" "$result"; fi
result=$($R compare-latest 60)
if echo "$result" | grep -q "regions="; then pass "comparison ($result)"; else fail "comparison" "$result"; fi
$R close-windows 10 >/dev/null
result=$($R editor-size-test 30)
if echo "$result" | grep -q "color=yellow" && [ "$(echo "$result" | sed -n 's/.*textFont=\([0-9]*\)->\([0-9]*\).*/\2/p')" -gt "$(echo "$result" | sed -n 's/.*textFont=\([0-9]*\)->.*/\1/p')" ]; then pass "screenshot + and - ($result)"; else fail "screenshot + and -" "$result"; fi
result=$($R video-size-test 60)
if echo "$result" | grep -q "100→150→400"; then pass "video mark sizes 100→150→400%"; else fail "video mark sizes" "$result"; fi
if echo "$result" | grep -q "picked=250 presetMark=250 remembered=250 blurSized=false"; then pass "video size picked with nothing selected goes to the next mark and is remembered; blur has none"; else fail "video size for the next mark" "$result"; fi
result=$($R cleanup-dryrun:0:0 60)
if echo "$result" | grep -q "wouldDelete=0"; then pass "clean-up with no limits deletes nothing"; else fail "clean-up dry run" "$result"; fi

section "several displays"
# wait_selected_screen <id> <seconds>: waits until the newest capture shows that display, prints the one shown.
wait_selected_screen() {
    local shown="" tries=0
    while [ "$tries" -lt $(($2 * 2)) ]; do
        shown=$($R clip-screens 10 | sed -n 's/^selected=\([^ ]*\) .*/\1/p')
        if [ "$shown" = "$1" ]; then break; fi
        # Poll step.
        sleep 0.5
        tries=$((tries + 1))
    done
    echo "$shown"
}
display_count=$($R screens 10 | tr ';' '\n' | grep -c ':')
if [ "$display_count" -ge 2 ]; then
    $R close-windows 10 >/dev/null
    $R save:4 90 >/dev/null
    screens=$($R clip-screens 10)
    first=$(echo "$screens" | tr ' ' '\n' | grep '^display-' | head -1 | cut -d= -f1)
    if [ "$(echo "$screens" | grep -o 'file:true' | wc -l | tr -d ' ')" -ge "$display_count" ]; then pass "clip keeps one video per display ($display_count)"; else fail "clip per display" "$screens"; fi
    one=$($R "select-screen:$first" 60)
    both=$($R select-screen:all 90)
    one_width=$(echo "$one" | sed -n 's/.*size=\([0-9]*\)x.*/\1/p')
    both_width=$(echo "$both" | sed -n 's/.*size=\([0-9]*\)x.*/\1/p')
    if [ -n "$one_width" ] && [ -n "$both_width" ] && [ "$both_width" -gt "$one_width" ]; then pass "clip switches between one display and side by side ($one_width → $both_width px)"; else fail "clip display switch" "$one / $both"; fi
    if echo "$one $both" | grep -q "staged=0.*staged=0"; then pass "switching displays leaves no stray files"; else fail "stray files after switching" "$one / $both"; fi
    # Picking the display that is already shown (original.* is the same file) changes nothing.
    $R "select-screen:$first" 60 >/dev/null
    again=$($R "select-screen:$first" 60)
    if echo "$again" | grep -q "^selected=$first .*staged=0"; then pass "picking the clip's shown display again works"; else fail "clip shown display again" "$again"; fi
    $R "select-screen:$first" 60 >/dev/null
    # The editor's own display picker, its segments pressed the way VoiceOver does.
    first_name=$(echo "$screens" | sed -n "s/.* $first=\([^(]*\)(clicks.*/\1/p")
    press_in video: "Screen: Side by side" >/dev/null
    picked_all=$(wait_selected_screen all 90)
    press_in video: "Screen: $first_name" >/dev/null
    picked_one=$(wait_selected_screen "$first" 90)
    if [ -n "$first_name" ] && [ "$picked_all" = all ] && [ "$picked_one" = "$first" ]; then pass "video \"Screen\" segments show side by side and one display"; else fail "video screen segments" "$first_name: $picked_all / $picked_one"; fi
    $R screenshot-full 40 >/dev/null
    # The editor opens a moment after the capture: wait for its display picker before pressing it.
    for _ in $(seq 20); do
        if $R controls:screenshot: 30 | grep -q "|Screen: Side by side"; then break; fi
        # Poll step.
        sleep 0.5
    done
    press_in screenshot: "Screen: Side by side" >/dev/null
    picked_all=$(wait_selected_screen all 60)
    press_in screenshot: "Screen: $first_name" >/dev/null
    picked_one=$(wait_selected_screen "$first" 60)
    if [ "$picked_all" = all ] && [ "$picked_one" = "$first" ]; then pass "screenshot \"Screen\" segments show side by side and one display"; else fail "screenshot screen segments" "$first_name: $picked_all / $picked_one"; fi
    $R close-windows 10 >/dev/null
    one=$($R "select-screen:$first" 60)
    both=$($R select-screen:all 60)
    one_width=$(echo "$one" | sed -n 's/.*size=\([0-9]*\)x.*/\1/p')
    both_width=$(echo "$both" | sed -n 's/.*size=\([0-9]*\)x.*/\1/p')
    if [ -n "$one_width" ] && [ -n "$both_width" ] && [ "$both_width" -gt "$one_width" ]; then pass "screenshot switches between one display and both ($one_width → $both_width px)"; else fail "screenshot display switch" "$one / $both"; fi
    $R "select-screen:$first" 60 >/dev/null
    again=$($R "select-screen:$first" 60)
    if echo "$again" | grep -q "^selected=$first .*staged=0"; then pass "picking the screenshot's shown display again works"; else fail "screenshot shown display again" "$again"; fi
    $R "select-screen:$first" 60 >/dev/null
else
    echo "SKIP  one display: connect a second one to check display switching"
fi

section "menu panel"
$R close-panel 10 >/dev/null
if [ "$($R press-status-item 10)" = "open=true" ]; then pass "click on the bear opens the panel"; else fail "panel opens"; fi
if [ "$($R press-status-item 10)" = "open=false" ]; then pass "second click closes it"; else fail "panel closes"; fi
$R press-status-item 10 >/dev/null
$R screenshot-full 40 >/dev/null
$R close-windows 10 >/dev/null
if [ "$($R press-status-item 10)" = "open=true" ]; then pass "panel still opens after a screenshot"; else fail "panel after screenshot"; fi
$R close-panel 10 >/dev/null

section "menu panel buttons: Capture"
# Every button is pressed the way VoiceOver presses it, and what it did is checked.
# With more than one display the menu offers "all displays" instead of "full screen".
display_count=$($R screens 10 | tr ';' '\n' | grep -c .)
full_screenshot="Screenshot full screen"
if [ "$display_count" -gt 1 ]; then full_screenshot="Screenshot all displays"; fi

# A tab that is not there stops press-menu before the label: nothing is pressed on the tab that shows.
result=$(press_menu "No such tab" "Settings…")
if [ "$result" = "tab not found: No such tab" ]; then pass "press-menu with a missing tab says so and presses nothing"; else fail "press-menu missing tab" "$result"; fi
$R close-panel 10 >/dev/null

for row in "30 s, ⌥⇧1|video:" "1 min, ⌥⇧2|video:" "3 min, ⌥⇧3|video:" "$full_screenshot|screenshot:"; do
    label="${row%%|*}"
    editor="${row##*|}"
    before=$(capture_count)
    result=$(press_menu Capture "$label")
    wait_for_value 15 "$((before + 1))" capture_count
    wait_for_text 15 "$editor" windows_now
    after=$(capture_count)
    opened=$(windows_now)
    if [ "$result" = "pressed" ] && [ "$after" -eq $((before + 1)) ] && [[ "$opened" == *"$editor"* ]]; then pass "menu \"$label\" saves a capture and opens its editor"; else fail "menu \"$label\"" "$result before=$before after=$after windows=$opened"; fi
    $R close-windows 10 >/dev/null
done

# "Edit" next to the environment goes to Settings → Bug reports, from another page.
$R settings-page:General 10 >/dev/null
edit_result=$(press_menu Capture "Edit")
wait_for_text 10 "|Include Device" $R controls:settings 30
shown=$($R controls:settings 30)
if [ "$edit_result" = "pressed" ] && [[ "$shown" == *"|Include Device"* ]]; then pass "menu environment \"Edit\" opens Settings on Bug reports"; else fail "menu environment Edit" "$edit_result"; fi
$R close-windows 10 >/dev/null

# Area, window and text pick with the system's screencapture; cancelling saves nothing.
for label in "Screenshot area, ⌥⇧4" "Screenshot window, ⌥⇧5" "Copy text from screen, ⌥⇧O"; do
    before=$(capture_count)
    result=$(press_menu Capture "$label")
    wait_for 10 pgrep -x screencapture
    if pgrep -x screencapture >/dev/null; then picking=true; else picking=false; fi
    pkill -x screencapture 2>/dev/null
    # Negative check: a wrongly saved capture would appear within this time.
    sleep 1
    after=$(capture_count)
    if [ "$result" = "pressed" ] && [ "$picking" = true ] && [ "$after" -eq "$before" ]; then pass "menu \"$label\" starts picking, cancelling saves nothing"; else fail "menu \"$label\"" "$result picking=$picking before=$before after=$after"; fi
done

result=$(press_menu Capture "Scrolling screenshot")
wait_for_text 10 region-picker windows_now
picker=$(windows_now)
$R post-key:53:none 10 >/dev/null
wait_for_no_text 10 region-picker windows_now
if [ "$result" = "pressed" ] && [[ "$picker" == *"region-picker"* ]] && [[ "$(windows_now)" != *"region-picker"* ]]; then pass "menu \"Scrolling screenshot\" opens the area picker, Esc closes it"; else fail "menu \"Scrolling screenshot\"" "$result windows=$picker"; fi
result=$(press_menu Capture "Scrolling screenshot")
wait_for_text 10 region-picker windows_now
$R controls:region-picker 30 | sed 's/ ;; /\n/g' | sed "s#^#region-picker|#" >> "$WORK/picker-controls.txt"
cancel_result=$(press_in region-picker Cancel)
wait_for_no_text 10 region-picker windows_now
if [ "$cancel_result" = "pressed" ] && grep -q "|Capture$" "$WORK/picker-controls.txt" && [[ "$(windows_now)" != *"region-picker"* ]]; then pass "area picker \"Cancel\" closes it, the scrolling one says \"Capture\""; else fail "area picker Cancel" "$cancel_result $(windows_now)"; fi

result=$(press_menu Capture "Pause buffer")
wait_for 10 status_starts paused
paused=$($R status 10)
result_start=$(press_menu Capture "Start buffer")
wait_for 15 status_starts running
running=$($R status 10)
if [[ "$paused" == paused* ]] && [[ "$running" == running* ]]; then pass "menu \"Pause buffer\" pauses it and \"Start buffer\" starts it again"; else fail "menu pause and start buffer" "$result/$result_start $paused / $running"; fi

for row in "Report a problem with $APP_NAME or suggest a feature on GitHub|feedback" "Open settings: buffer, shortcuts, storage and more|settings"; do
    label="${row%%|*}"
    window="${row##*|}"
    result=$(press_menu Capture "$label")
    wait_for_text 10 "$window" windows_now
    if [[ "$(windows_now)" == *"$window"* ]]; then pass "menu \"$label\" opens the $window window"; else fail "menu \"$label\"" "$result $(windows_now)"; fi
    $R close-windows 10 >/dev/null
done
$R close-panel 10 >/dev/null

section "menu panel buttons: Record"
before=$(capture_count)
result=$(press_menu Record "Start recording")
wait_for_text 15 "recording=true paused=false" tools_now
started=$(tools_now)
paused_result=$(press_menu Record "Pause")
wait_for_text 10 "recording=true paused=true" tools_now
paused=$(tools_now)
resumed_result=$(press_menu Record "Resume")
wait_for_text 10 "recording=true paused=false" tools_now
resumed=$(tools_now)
stop_result=$(press_menu Record "Stop")
wait_for_value 20 "$((before + 1))" capture_count
after=$(capture_count)
if [[ "$started" == *"recording=true paused=false"* ]]; then pass "menu \"Start recording\" records the full screen"; else fail "menu \"Start recording\"" "$result $started"; fi
if [[ "$paused" == *"recording=true paused=true"* && "$resumed" == *"recording=true paused=false"* ]]; then pass "menu \"Pause\" and \"Resume\" pause and resume the recording"; else fail "menu pause and resume" "$paused_result $paused / $resumed_result $resumed"; fi
if [ "$after" -eq $((before + 1)) ] && [[ "$(tools_now)" == *"recording=false"* ]]; then pass "menu \"Stop\" saves the recording"; else fail "menu \"Stop\"" "$stop_result before=$before after=$after"; fi
$R close-windows 10 >/dev/null

result=$(press_menu Record "Area…")
target=$(tools_now)
start_result=$(press_menu Record "Start recording")
wait_for_text 10 region-picker windows_now
picker=$(windows_now)
$R post-key:53:none 10 >/dev/null
# Negative check: a recording wrongly started by Esc would show within this time.
sleep 1
not_started=$(tools_now)
# "All displays" when the app keeps every display.
full_label="Full screen"
if [ "$($R screens 10 | tr ';' '\n' | grep -c .)" -gt 1 ] && [ "$(setting_value captureAllDisplays)" = 1 ]; then full_label="All displays"; fi
full_result=$(press_menu Record "$full_label")
full=$(tools_now)
if [[ "$target" == *"target=area"* && "$picker" == *"region-picker"* && "$not_started" == *"recording=false"* && "$full" == *"target=screens"* ]]; then pass "menu \"Area…\" records a picked area, Esc cancels, \"$full_label\" switches back"; else fail "menu area and full screen" "$result $target / $start_result $picker / $not_started / $full_result $full"; fi

result=$(press_menu Record "Draw")
wait_for_text 10 "drawing=true" tools_now
drawing=$(tools_now)
$R post-key:53:none 10 >/dev/null
wait_for_text 10 "drawing=false" tools_now
if [[ "$drawing" == *"drawing=true"* && "$(tools_now)" == *"drawing=false"* ]]; then pass "menu \"Draw\" starts drawing on the screen, Esc ends it"; else fail "menu \"Draw\"" "$result $drawing"; fi
# Esc ends drawing, the marks stay until closed.
$R close-windows 10 >/dev/null

result=$(press_menu Record "Measure on screen")
wait_for_text 10 "ruler=true" tools_now
measuring=$(tools_now)
$R ruler-stop 10 >/dev/null
if [[ "$measuring" == *"ruler=true"* ]]; then pass "menu \"Measure on screen\" opens the ruler"; else fail "menu \"Measure on screen\"" "$result $measuring"; fi

result=$(press_menu Record "Pick a color, copies hex")
wait_for_text 10 "picking=true" tools_now
picking=$(tools_now)
$R post-key:53:none 10 >/dev/null
wait_for_text 10 "picking=false" tools_now
if [[ "$picking" == *"picking=true"* && "$(tools_now)" == *"picking=false"* ]]; then pass "menu \"Pick a color\" opens the color loupe, Esc closes it"; else fail "menu \"Pick a color\"" "$result $picking"; fi

permissions=$($R permissions 10)
for row in "Mic|recordMicrophone|microphone=true" "System audio|recordSystemAudio|screen=true"; do
    label="${row%%|*}"
    rest="${row#*|}"
    setting="${rest%%|*}"
    needs="${rest##*|}"
    if [[ "$permissions" != *"$needs"* ]]; then
        echo "SKIP  menu \"$label\": needs $needs, macOS would ask"
        continue
    fi
    before_value=$(setting_value "$setting")
    press_menu Record "$label" >/dev/null
    wait_for 10 setting_differs "$setting" "$before_value"
    after_value=$(setting_value "$setting")
    press_menu Record "$label" >/dev/null
    wait_for_value 10 "$before_value" setting_value "$setting"
    back_value=$(setting_value "$setting")
    if [ "$before_value" != "$after_value" ] && [ "$before_value" = "$back_value" ]; then pass "menu \"$label\" turns $setting on and off"; else fail "menu \"$label\"" "$before_value → $after_value → $back_value"; fi
done
if [[ "$permissions" == *"camera=true"* ]]; then
    press_menu Record "Camera" >/dev/null
    wait_for_text 10 camera windows_now
    camera_on=$(windows_now)
    press_menu Record "Camera" >/dev/null
    wait_for_no_text 10 camera windows_now
    if [[ "$camera_on" == *"camera"* ]]; then pass "menu \"Camera\" shows the camera bubble"; else fail "menu \"Camera\"" "$camera_on"; fi
else
    echo "SKIP  menu \"Camera\": needs camera=true, macOS would ask"
fi
$R close-panel 10 >/dev/null

section "menu panel buttons: Tools"
# Each chip opens the toolbox on its tool.
for row in "{ } JSON|JSON" "XML|XML" "YAML|YAML" "HTML|HTML" "SQL|SQL" "GraphQL|GraphQL" "JWT|JWT" "Base64|Base64" "URL|URL encode" "&; Entities|HTML entities" "Time|Time & dates" "Time zones|Time zones" "⇄ Convert|JSON ↔ YAML ↔ XML ↔ CSV" "0x · Color · Case|Numbers, colors, case" "UUID · Hash|UUID · hash" "Test data|Test data" "Regex|Regex" "QR|QR code"; do
    label="${row%%|*}"
    tool="${row##*|}"
    result=$(press_menu Tools "$label")
    wait_for_value 10 "tool=$tool" $R toolbox-tool 10
    shown=$($R toolbox-tool 10)
    if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"toolbox"* ]] && [ "$shown" = "tool=$tool" ]; then pass "menu \"$label\" opens the toolbox on $tool"; else fail "menu \"$label\"" "$result $shown"; fi
done
$R close-windows 10 >/dev/null
printf '' | pbcopy
result=$(press_menu Tools "All tools")
wait_for_text 10 toolbox windows_now
if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"toolbox"* ]]; then pass "menu \"All tools\" opens the toolbox"; else fail "menu \"All tools\"" "$result $(windows_now)"; fi
$R close-windows 10 >/dev/null
# "Compare…" next to the world clock compares times across cities.
result=$(press_menu Tools "Compare…")
wait_for_value 10 "tool=Time zones" $R toolbox-tool 10
shown=$($R toolbox-tool 10)
if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"toolbox"* ]] && [ "$shown" = "tool=Time zones" ]; then pass "menu \"Compare…\" opens the time zone comparison"; else fail "menu \"Compare…\"" "$result $shown $(windows_now)"; fi
$R close-windows 10 >/dev/null

section "menu panel buttons: Recent and Space"
result=$(press_menu Recent "All captures")
wait_for_text 10 history windows_now
if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"history"* ]]; then pass "menu \"All captures\" opens the history"; else fail "menu \"All captures\"" "$result $(windows_now)"; fi
$R close-windows 10 >/dev/null
# The newest capture row opens its editor. The rows are read with the panel open on Recent.
$R close-panel 10 >/dev/null
$R press-status-item 10 >/dev/null
$R press:menubar:Recent 10 >/dev/null
wait_for 10 recent_capture_shown
newest=$($R controls:menubar 30 | sed 's/ ;; /\n/g' | grep -E "(ago|just now)$" | head -1 | cut -d'|' -f2)
result=$(press_menu Recent "$newest")
wait_for 10 capture_editor_open
if [ -n "$newest" ] && [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"screenshot:"* || "$(windows_now)" == *"video:"* ]]; then pass "a recent capture opens in its editor ($newest)"; else fail "a recent capture opens" "$newest $result $(windows_now)"; fi
$R close-windows 10 >/dev/null
# "Open" on the Captures row opens the history. The menu shows only the four biggest categories,
# so Captures is there only when this Mac's captures are big: then it is pressed in the menu,
# otherwise on the same row in the Disk Space window, which lists every category.
$R close-panel 10 >/dev/null
$R press-status-item 10 >/dev/null
$R press:menubar:Space 10 >/dev/null
if $R controls:menubar 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -qxF "Open"; then
    where="menu"
    result=$(press_menu Space "Open")
else
    where="Disk Space window"
    $R close-panel 10 >/dev/null
    $R open-space:Clean\ up 10 >/dev/null
    wait_for 10 space_control_shown "Open"
    result=$(press_in space "Open")
fi
wait_for_text 10 history windows_now
if [ "$result" = "pressed" ] && window_open history; then pass "Space \"Open\" on Captures opens the history ($where)"; else fail "Space \"Open\" on Captures ($where)" "$result $(windows_now)"; fi
$R close-windows 10 >/dev/null
for row in "All categories|space" "What takes space…|space"; do
    label="${row%%|*}"
    window="${row##*|}"
    result=$(press_menu Space "$label")
    wait_for_text 10 "$window" windows_now
    if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"$window"* ]]; then pass "Space tab \"$label\" opens the $window window"; else fail "Space tab \"$label\"" "$result $(windows_now)"; fi
    $R close-windows 10 >/dev/null
done
# "Review…" on a category opens the window on its list; the menu itself removes nothing and never
# searches for projects. On a made-up home, so nothing real is listed.
fake_home=$($R space-fake-home:on 60)
result=$(press_menu Space "Review App caches")
wait_for_text 10 "rows=2 checked=2 " $R space-review-state:appCaches 10
listed=$($R space-review-state:appCaches 10)
if [ "$result" = "pressed" ] && window_open space && [[ "$listed" == *"rows=2 checked=2 "* ]] && [ -f "$fake_home/Library/Caches/com.example.app/blob.bin" ]; then pass "Space tab \"Review…\" opens the window on the list and keeps the files"; else fail "Space tab Review" "$result $listed"; fi
$R close-windows 10 >/dev/null
result=$(press_menu Space "Find projects…")
wait_for 10 window_open space
# Negative check: a wrongly started search would show within this time.
sleep 1
wait_for_text 10 "list=false" $R space-review-state:projects 10
listed=$($R space-review-state:projects 10)
if [ "$result" = "pressed" ] && window_open space && [[ "$listed" == *"list=false"* && "$listed" == *"scanning=false"* ]]; then pass "Space tab \"Find projects…\" opens the project list without searching"; else fail "Space tab Find projects…" "$result $listed"; fi
$R close-windows 10 >/dev/null
$R space-fake-home:off 60 >/dev/null
$R close-panel 10 >/dev/null

section "history window buttons"
# Two screenshots of our own to select, compare and delete; the person's captures are only read.
$R screenshot-full 40 >/dev/null
# Real time: the screenshot is saved and its editor opens before the next one is taken.
sleep 1
$R screenshot-full 40 >/dev/null
# Real time: the screenshot is saved and its editor opens before the next one is taken.
sleep 1
$R close-windows 10 >/dev/null
read -r own_id _ <<< "$($R latest-capture 10)"
cards_now() { $R controls:history 30 | sed 's/ ;; /\n/g' | grep -E "^AXButton\|(Screenshot|Clip): " | cut -d'|' -f2-; }
card_total() { cards_now | wc -l | tr -d ' '; }
# Every card shown belongs to the app (the sidebar filter has applied).
only_app_cards() { [ "$(cards_now | grep -cv ": $1, ")" = "0" ]; }
press_menu Recent "All captures" >/dev/null
wait_for_text 10 "Screenshot: " cards_now
all_cards=$(cards_now | wc -l | tr -d ' ')
if [ "$all_cards" -ge 2 ]; then pass "history lists every capture as a card ($all_cards)"; else fail "history cards" "$all_cards"; fi

# Filters: only screenshots, only clips, all again.
press_in history Screenshots >/dev/null
wait_for_no_text 10 "Clip: " cards_now
if [ "$(cards_now | grep -c '^Clip: ')" = "0" ] && [ "$(cards_now | grep -c '^Screenshot: ')" -ge 2 ]; then pass "history filter \"Screenshots\" shows only screenshots"; else fail "history filter Screenshots" "$(cards_now | head -3)"; fi
press_in history Videos >/dev/null
wait_for_no_text 10 "Screenshot: " cards_now
if [ "$(cards_now | grep -c '^Screenshot: ')" = "0" ]; then pass "history filter \"Videos\" shows only clips"; else fail "history filter Videos" "$(cards_now | head -3)"; fi
press_in history All >/dev/null
wait_for_value 10 "$all_cards" card_total
if [ "$(cards_now | wc -l | tr -d ' ')" = "$all_cards" ]; then pass "history filter \"All\" shows everything again"; else fail "history filter All" "$(cards_now | wc -l)"; fi

# An app in the sidebar shows only its captures; "All" shows everything again.
first_app=$($R controls:history 30 | sed 's/ ;; /\n/g' | grep -E "^AXButton\|App: " | head -1 | sed 's/^AXButton|App: //')
press_in history "App: $first_app" >/dev/null
wait_for 10 only_app_cards "$first_app"
others=$(cards_now | grep -cv ": $first_app, ")
shown_app=$(cards_now | wc -l | tr -d ' ')
press_in history All >/dev/null
wait_for_value 10 "$all_cards" card_total
if [ -n "$first_app" ] && [ "$shown_app" -ge 1 ] && [ "$others" = "0" ] && [ "$(cards_now | wc -l | tr -d ' ')" = "$all_cards" ]; then pass "history sidebar app \"$first_app\" shows only its captures"; else fail "history sidebar app" "$first_app: $shown_app shown, $others of other apps"; fi

# Search: nothing matches a made-up word, clearing it brings the cards back.
$R "set-value:history:Search by app, URL…=zz-no-such-capture" 10 >/dev/null
wait_for_value 10 0 card_total
searched=$(cards_now | wc -l | tr -d ' ')
$R "set-value:history:Search by app, URL…=" 10 >/dev/null
wait_for_value 10 "$all_cards" card_total
if [ "$searched" = "0" ] && [ "$(cards_now | wc -l | tr -d ' ')" = "$all_cards" ]; then pass "history search hides what does not match and clearing it shows all"; else fail "history search" "$searched then $(cards_now | wc -l)"; fi

# A card opens its editor.
first_card=$(cards_now | head -1)
press_in history "$first_card" >/dev/null
wait_for 10 capture_editor_open
if [[ "$(windows_now)" == *"screenshot:"* || "$(windows_now)" == *"video:"* ]]; then pass "history card opens the capture in its editor"; else fail "history card opens" "$first_card $(windows_now)"; fi
$R close-windows 10 >/dev/null

# Select two screenshots: Step guide and Compare open their windows, Done leaves selecting.
open_history_selecting() {
    $R close-windows 10 >/dev/null
    press_menu Recent "All captures" >/dev/null
    wait_for_text 10 "Screenshot: " cards_now
    press_in history Screenshots >/dev/null
    press_in history Select >/dev/null
    # Real time: the selection mode redraws the cards; the cards expose no selected state.
    sleep 0.5
    press_in history "$(cards_now | sed -n 1p)" >/dev/null
    press_in history "$(cards_now | sed -n 2p)" >/dev/null
    # Real time: the selection mode redraws the cards; the cards expose no selected state.
    sleep 0.5
}
open_history_selecting
press_in history "Step guide" >/dev/null
wait_for_text 10 step-guide windows_now
if [[ "$(windows_now)" == *"step-guide"* ]]; then pass "history \"Select\" two screenshots, \"Step guide\" opens the guide"; else fail "history Step guide" "$(windows_now)"; fi
open_history_selecting
press_in history Compare >/dev/null
wait_for_text 10 compare windows_now
if [[ "$(windows_now)" == *"compare"* ]]; then pass "history \"Compare\" opens the comparison of the two picked"; else fail "history Compare" "$(windows_now)"; fi
open_history_selecting
press_in history Done >/dev/null
wait_for_no_text 10 "|Done" $R controls:history 30
history_controls=$($R controls:history 30)
if [[ "$history_controls" == *"|Select"* && "$history_controls" != *"|Done"* ]]; then pass "history \"Done\" stops selecting"; else fail "history Done" "$history_controls"; fi

# Open folder hands the captures folder to Finder (recorded, not opened).
$R system-actions:start 10 >/dev/null
press_in history "Open folder" >/dev/null
opened=$($R system-actions:read 10)
if [[ "$opened" == "open "*"/Captures"* ]]; then pass "history \"Open folder\" opens the captures folder"; else fail "history Open folder" "$opened"; fi

# The "More actions" menu of the first card, our own screenshot (the newest): every item does its thing.
if [[ "$history_controls" == *"AXMenuButton|More actions"* ]]; then pass "history cards have a \"More actions\" menu"; else fail "history More actions" "$history_controls"; fi
$R close-windows 10 >/dev/null
press_menu Recent "All captures" >/dev/null
wait_for_text 10 "Screenshot: " cards_now
card_menu() { $R "choose:history:More actions => $1" 10; }
card_menu "Open" >/dev/null
wait_for_text 10 "$own_id" windows_now
if [[ "$(windows_now)" == *"$own_id"* ]]; then pass "history menu \"Open\" opens the editor"; else fail "history menu Open" "$(windows_now)"; fi
card_menu "Show original in Finder" >/dev/null
if [[ "$($R system-actions:read 10)" == *"reveal "*"$own_id"* ]]; then pass "history menu \"Show original in Finder\" shows the file"; else fail "history menu reveal" "$($R system-actions:read 10)"; fi
card_menu "Copy bug report (Markdown)" >/dev/null
if pbpaste | grep -q "^## Steps to reproduce"; then pass "history menu \"Copy bug report (Markdown)\" copies the report"; else fail "history menu Markdown" "$(pbpaste | head -2)"; fi
card_menu "Copy bug report (Jira wiki)" >/dev/null
if pbpaste | grep -q "^h2. Steps to reproduce"; then pass "history menu \"Copy bug report (Jira wiki)\" copies the report"; else fail "history menu Jira" "$(pbpaste | head -2)"; fi
card_menu "Copy environment" >/dev/null
if pbpaste | grep -q "^\*\*Environment\*\*"; then pass "history menu \"Copy environment\" copies the environment"; else fail "history menu environment" "$(pbpaste | head -2)"; fi
# Log and crash report items are there only for captures that have them (the self-test checks a
# crash clip's menu has both).
own_menu=$($R "menu-items:history:More actions" 10)
if [[ "$own_menu" == *"Copy environment"* && "$own_menu" != *"Open system log"* && "$own_menu" != *"Open crash report"* ]]; then pass "history menu \"Open system log\" and \"Open crash report\" only for captures that have them"; else fail "history menu log items" "$own_menu"; fi
$R system-actions:stop 10 >/dev/null

# Delete… asks first; "Delete" in the question removes our screenshot.
$R close-windows 10 >/dev/null
press_menu Recent "All captures" >/dev/null
wait_for_text 10 "Screenshot: " cards_now
before=$(capture_count)
card_menu "Delete…" >/dev/null
# Negative check: the capture must still be there while the question is open.
sleep 0.5
asked=$(capture_count)
press_in history Delete >/dev/null
wait_for_value 10 "$((before - 1))" capture_count
after=$(capture_count)
if [ "$asked" = "$before" ] && [ "$after" = "$((before - 1))" ] && [[ "$($R latest-capture 10)" != "$own_id"* ]]; then pass "history menu \"Delete…\" asks, then deletes only that capture"; else fail "history Delete" "$before → $asked → $after"; fi
$R close-windows 10 >/dev/null

section "disk space buttons"
# Everything here works on a made-up home and Applications folder; Move to Trash is recorded, not done.
fake_home=$($R space-fake-home:on 60)
space_controls() { $R controls:space 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2-; }
delete_label_shown() { space_controls | grep -qE "^Delete [0-9]+ items?, "; }
space_state() { $R space-state 10; }
$R open-space:Clean\ up 10 >/dev/null
# open-space opens a new window: wait for its page, the old window counts as "open" before it.
wait_for 10 space_control_shown "Review App caches"
$R system-actions:start 10 >/dev/null

# Review…: the list of the category in place of the categories; the footer asks first, Cancel
# keeps the files, the confirmation deletes the ticked ones. Only on the made-up home.
if [ -z "$fake_home" ] || [ ! -d "$fake_home/Library/Caches" ] || [[ "$($R space-review-state:appCaches 10)" == refused* ]]; then
    fail "disk space buttons need the made-up home" "$fake_home"
else
    press_in space "Review App caches" >/dev/null
    wait_for 10 delete_label_shown
    delete_label=$(space_controls | grep -E "^Delete [0-9]+ items?, " | head -1)
    press_in space "$delete_label" >/dev/null
    asked=$(space_controls | grep -c "^Cancel$")
    press_in space Cancel >/dev/null
    no_cancel() { ! space_controls | grep -q "^Cancel$"; }
    wait_for 10 no_cancel
    if [ -n "$delete_label" ] && [ "$asked" = "1" ] && [ -f "$fake_home/Library/Caches/com.example.app/blob.bin" ] && ! space_controls | grep -q "^Cancel$"; then pass "Space \"Review…\" lists the category, its footer asks first and \"Cancel\" keeps the files"; else fail "Space Review, Cancel" "$delete_label asked=$asked"; fi
    press_in space "$delete_label" >/dev/null
    press_in space "$delete_label" >/dev/null
    caches_cleaned() { [ ! -f "$fake_home/Library/Caches/com.example.app/blob.bin" ] && [[ "$(space_state)" == *"appCaches=Zero KB"* ]]; }
    wait_for 15 caches_cleaned
    if [ ! -f "$fake_home/Library/Caches/com.example.app/blob.bin" ] && [[ "$(space_state)" == *"appCaches=Zero KB"* ]]; then pass "Space \"Delete …\" cleans the category"; else fail "Space Delete" "$(space_state)"; fi
    press_in space "All categories" >/dev/null
fi

# Measure again picks up a new cache file.
mkdir -p "$fake_home/Library/Caches/com.example.other"
dd if=/dev/zero of="$fake_home/Library/Caches/com.example.other/new.bin" bs=1m count=2 2>/dev/null
press_in space "Measure again" >/dev/null
wait_for_text 20 "appCaches=2" space_state
if [[ "$(space_state)" == *"appCaches=2"* ]]; then pass "Space \"Measure again\" measures fresh sizes"; else fail "Space Measure again" "$(space_state)"; fi

# Our captures open in the history.
press_in space Open >/dev/null
wait_for_text 10 history windows_now
if [[ "$(windows_now)" == *"history"* ]]; then pass "Space \"Open\" on the captures row opens the history"; else fail "Space Open" "$(windows_now)"; fi

# Folders: the app data switch flips and comes back, Scan and Stop.
press_in space Folders >/dev/null
wait_for_text 10 "Include other apps" space_controls
before=$(space_state)
press_in space "Include other apps' private data (Docker, Slack, Telegram…). macOS asks once." >/dev/null
flipped=$(space_state)
press_in space "Include other apps' private data (Docker, Slack, Telegram…). macOS asks once." >/dev/null
app_data_before=$(echo "$before" | tr ' ' '\n' | grep '^appData=')
app_data_flipped=$(echo "$flipped" | tr ' ' '\n' | grep '^appData=')
if [ -n "$app_data_before" ] && [ "$app_data_before" != "$app_data_flipped" ] && [[ "$(space_state)" == *"$app_data_before"* ]]; then pass "Space switch \"Include other apps' private data\" turns on and off"; else fail "Space app data switch" "$before / $flipped"; fi
press_in space "Scan home folder and Applications" >/dev/null
wait_for_text 10 "Stop" space_controls
press_in space Stop >/dev/null
wait_for_text 10 "scan=idle" space_state
if [[ "$(space_state)" == *"scan=idle"* ]]; then pass "Space \"Stop\" stops the scan"; else fail "Space Stop" "$(space_state)"; fi
press_in space "Scan home folder and Applications" >/dev/null
for _ in $(seq 1 180); do
    [[ "$(space_state)" == *"scan=done"* ]] && break
    # Poll step of the scan wait.
    sleep 1
done
if [[ "$(space_state)" == *"scan=done"* ]]; then pass "Space \"Scan home folder and Applications\" finishes a scan"; else fail "Space Scan" "$(space_state)"; fi

# Folder rows open, breadcrumbs go back, Show in Finder shows the folder.
press_in space "$(space_controls | grep -E "^Folder Home, " | head -1)" >/dev/null
# Library has subfolders; a folder with only files (Downloads) does not open.
press_in space "$(space_controls | grep -E "^Folder Library, " | head -1)" >/dev/null
opened_folder=$(space_state)
press_in space "Show in Finder" >/dev/null
press_in space "Back to Home" >/dev/null
back_once=$(space_state)
press_in space "This Mac" >/dev/null
if [[ "$opened_folder" == *"folder=Home > Library" && "$back_once" == *"folder=Home" && "$(space_state)" == *"folder=" ]]; then pass "Space folder rows open and \"Back to\" / \"This Mac\" go back"; else fail "Space folders" "$opened_folder / $back_once / $(space_state)"; fi
if [[ "$($R system-actions:read 10)" == *"reveal $fake_home/Library"* ]]; then pass "Space \"Show in Finder\" shows the open folder"; else fail "Space Show in Finder" "$($R system-actions:read 10)"; fi

# Largest files: Show, Move to Trash asks, Keep, Move.
press_in space "Largest files" >/dev/null
wait_for_text 10 "Show test-big.bin in Finder" space_controls
press_in space "Show test-big.bin in Finder" >/dev/null
if [[ "$($R system-actions:read 10)" == *"reveal $fake_home/Downloads/test-big.bin"* ]]; then pass "Space \"Show\" shows the file in Finder"; else fail "Space Show file" "$($R system-actions:read 10)"; fi
press_in space "Move test-big.bin to Trash" >/dev/null
press_in space "Keep test-big.bin" >/dev/null
if space_controls | grep -q "^Move test-big.bin to Trash$" && [[ "$($R system-actions:read 10)" != *"trash "* ]]; then pass "Space \"Move to Trash\" asks first and \"Cancel\" keeps the file"; else fail "Space Move to Trash, Cancel"; fi
press_in space "Move test-big.bin to Trash" >/dev/null
press_in space "Move test-big.bin to the Trash now" >/dev/null
if [[ "$($R system-actions:read 10)" == *"trash $fake_home/Downloads/test-big.bin"* ]] && ! space_controls | grep -q "test-big.bin"; then pass "Space \"Move\" moves the file to the Trash and drops its row"; else fail "Space Move" "$($R system-actions:read 10)"; fi

# Scan again from the folder list starts a fresh scan.
press_in space Folders >/dev/null
press_in space "Scan again" >/dev/null
wait_for_text 10 "scan=running" space_state
again=$(space_state)
for _ in $(seq 1 180); do
    [[ "$(space_state)" == *"scan=done"* ]] && break
    # Poll step of the scan wait.
    sleep 1
done
if [[ "$again" == *"scan=running"* && "$(space_state)" == *"scan=done"* ]]; then pass "Space \"Scan again\" scans again"; else fail "Space Scan again" "$again"; fi
$R system-actions:stop 10 >/dev/null
$R close-windows 10 >/dev/null
$R space-fake-home:off 60 >/dev/null

section "space review"
# Review lists with checkboxes, on a made-up home whose Trash is <home>/.TestTrash: nothing here
# reaches the person's files or their Trash. space-fake-home also sets the project settings for
# the test (projects in ~/Projects, old after 30 days, to the Trash) and :off puts them back.
$R close-windows 10 >/dev/null
settings_before="$(setting_value projectRoots)/$(setting_value oldProjectDays)/$(setting_value projectFoldersToTrash)/$(setting_value dependencyKinds)/$(setting_value hiddenCacheRows)"
# A Ctrl-C or a crash in this section still puts the project settings back (space-fake-home:off),
# then does what the runner's own exit trap does.
space_review_exit() {
    $R space-fake-home:off 60 >/dev/null
    if declare -F restore_running_app >/dev/null; then restore_running_app; fi
}
trap space_review_exit EXIT
trap 'exit 130' INT TERM
fake_home=$($R space-fake-home:on 60)
review_state() { $R "space-review-state:$1" 10; }
review_controls() { $R controls:space 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2-; }
# review_settled <list>: its search or removal is over.
review_settled() { local state; state=$(review_state "$1"); [[ "$state" == *"scanning=false"* && "$state" == *"removing=false"* ]]; }
# wait_review <list>: until its search or removal is over. The press before it answers only after
# the app's moment for redrawing, and the search or removal has started by then (it starts on the press).
wait_review() { wait_for 30 review_settled "$1"; }
# find_projects <button>: presses Find projects / Find again in the window on the project list.
find_projects() {
    $R "open-space:Clean up:projects" 10 >/dev/null
    # The button itself, on the project list: the window is "open" before it switches to the list.
    wait_for 10 space_control_shown "$1"
    press_in space "$1" >/dev/null
    wait_review projects
}
if [ ! -d "$fake_home/Projects/old-app" ] || [[ "$(review_state projects)" == refused* ]]; then
    fail "space review needs the made-up home" "$fake_home"
else
    $R system-actions:start 10 >/dev/null
    $R open-space:Clean\ up 10 >/dev/null
    wait_for 10 space_control_shown "Find projects…"
    # The Projects row opens the list without searching; the search waits 2 s here, so Stop has
    # something to stop.
    press_in space "Find projects…" >/dev/null
    review_list_shown() { review_controls | grep -qx "Find projects"; }
    wait_for 10 review_list_shown
    opened=$(review_state projects)
    if [[ "$opened" == *"list=false"* && "$opened" == *"scanning=false"* ]] && review_controls | grep -qx "Find projects"; then pass "Space \"Find projects…\" opens the project list without searching"; else fail "Space Find projects…" "$opened"; fi
    press_in space "Find projects" >/dev/null
    wait_for_text 10 "scanning=true" $R space-review-state:projects 10
    searching=$(review_state projects)
    press_in space Stop >/dev/null
    wait_for_text 10 "scanning=false" $R space-review-state:projects 10
    stopped=$(review_state projects)
    if [[ "$searching" == *"scanning=true"* && "$stopped" == *"scanning=false"* && "$stopped" == *"list=false"* ]]; then pass "Space project search \"Stop\" stops the search and lists nothing"; else fail "Space project Stop" "$searching / $stopped"; fi
    # Nothing more to stop: the searches below start at once instead of after 2 s.
    $R space-scan-delay:0 10 >/dev/null

    # Find projects: old-app and fresh-app, only the old one ticked; the build folder of no Gradle
    # project, the node_modules in git and the link back to the home folder are not listed.
    press_in space "Find projects" >/dev/null
    wait_review projects
    found=$(review_state projects)
    boxes=$($R controls:space 30 | sed 's/ ;; /\n/g' | grep "^AXCheckBox|" | cut -d'|' -f2-)
    old_box=$(echo "$boxes" | grep "/old-app/node_modules$" | head -1)
    fresh_box=$(echo "$boxes" | grep "/fresh-app/node_modules$" | head -1)
    if [[ "$found" == *"rows=2 checked=1 "* ]] && [ -n "$old_box" ] && [ -n "$fresh_box" ] && ! echo "$boxes" | grep -qE "plain|vendored|link-home"; then pass "Space \"Find projects\" lists old-app and fresh-app, ticks only the old one"; else fail "Space Find projects" "$found / $boxes"; fi
    press_in space "$fresh_box" >/dev/null
    ticked=$(review_state projects)
    press_in space "$fresh_box" >/dev/null
    unticked=$(review_state projects)
    if [[ "$ticked" == *"checked=2 "* && "$unticked" == *"checked=1 "* ]]; then pass "Space review checkbox ticks and unticks its folder"; else fail "Space review checkbox" "$ticked / $unticked"; fi
    press_in space "Select none" >/dev/null
    none=$(review_state projects)
    footer_off=$(review_controls | grep -cE "^Move 0 folders, ")
    press_in space "Select all" >/dev/null
    all=$(review_state projects)
    press_in space "Select none" >/dev/null
    press_in space "$old_box" >/dev/null
    if [[ "$none" == *"checked=0 selected=0 "* && "$all" == *"checked=2 "* && "$footer_off" = "1" ]]; then pass "Space review \"Select all\" and \"Select none\" tick and untick every row"; else fail "Space review Select all/none" "$none / $all / footer $footer_off"; fi
    press_in space "Show $old_box in Finder" >/dev/null
    if [[ "$($R system-actions:read 10)" == *"reveal $old_box"* ]]; then pass "Space review \"Show\" shows the folder in Finder"; else fail "Space review Show" "$($R system-actions:read 10)"; fi

    # Settings → Storage → Project clean-up, on the made-up home's settings.
    open_settings
    $R settings-page:Storage 10 >/dev/null
    wait_for_text 10 "Old after " $R controls:settings 30
    storage_controls=$($R controls:settings 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2-)
    days_label=$(echo "$storage_controls" | grep -E "^Old after [0-9]+ days$" | head -1)
    days_before=$(setting_value oldProjectDays)
    press_now settings "$days_label#increment" >/dev/null
    wait_for 5 setting_differs oldProjectDays "$days_before"
    days_up=$(setting_value oldProjectDays)
    # The stepper's label says the new days once the window has redrawn.
    wait_for_text 5 "|Old after $days_up days" $R controls:settings 30
    days_label=$($R controls:settings 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -E "^Old after [0-9]+ days$" | head -1)
    press_now settings "$days_label#decrement" >/dev/null
    wait_for_value 5 "$days_before" setting_value oldProjectDays
    days_back=$(setting_value oldProjectDays)
    if [ -n "$days_label" ] && [ "$days_up" = "$((days_before + 1))" ] && [ "$days_back" = "$days_before" ]; then pass "settings \"Old after\" steps the days up and down ($days_before → $days_up → $days_back)"; else fail "settings Old after" "$days_label: $days_before → $days_up → $days_back"; fi
    # Old after 90 days: old-app (60 days) is no longer ticked.
    $R setting-write:oldProjectDays=90 10 >/dev/null
    find_projects "Find again"
    later=$(review_state projects)
    $R "setting-write:oldProjectDays=$days_before" 10 >/dev/null
    find_projects "Find again"
    if [[ "$later" == *"rows=2 checked=0 "* && "$(review_state projects)" == *"rows=2 checked=1 "* ]]; then pass "Space \"Find again\" ticks by the \"Old after\" days of the settings"; else fail "Space Old after 90" "$later / $(review_state projects)"; fi

    # The Trash switch: off, the footer deletes instead of moving to the Trash.
    trash_before=$(setting_value projectFoldersToTrash)
    press_now settings "Move project folders to the Trash" >/dev/null
    wait_for 5 setting_differs projectFoldersToTrash "$trash_before"
    trash_off=$(setting_value projectFoldersToTrash)
    find_projects "Find again"
    delete_footer=$(review_controls | grep -cE "^Delete 1 folder, ")
    press_now settings "Move project folders to the Trash" >/dev/null
    wait_for_value 5 "$trash_before" setting_value projectFoldersToTrash
    trash_back=$(setting_value projectFoldersToTrash)
    find_projects "Find again"
    trash_footer=$(review_controls | grep -cE "^Move 1 folder, .+ to the Trash$")
    if [ "$trash_before" = "1" ] && [ "$trash_off" = "0" ] && [ "$trash_back" = "1" ] && [ "$delete_footer" = "1" ] && [ "$trash_footer" = "1" ]; then pass "settings \"Move project folders to the Trash\" turns off (the footer says Delete) and on"; else fail "settings Trash switch" "$trash_before/$trash_off/$trash_back footer $delete_footer/$trash_footer"; fi

    # Each kind switch flips its kind; with Node modules off nothing is found.
    kinds_before=$(setting_value dependencyKinds)
    flipped=0
    for kind in "Node modules" "Python environments" "CocoaPods" "Rust build output" "Swift build output" "Gradle build output" "Gradle project cache"; do
        press_now settings "$kind" >/dev/null
        wait_for 5 setting_differs dependencyKinds "$kinds_before"
        off=$(setting_value dependencyKinds)
        if [ "$kind" = "Node modules" ]; then
            find_projects "Find again"
            without_node=$(review_state projects)
        fi
        press_now settings "$kind" >/dev/null
        wait_for_value 5 "$kinds_before" setting_value dependencyKinds
        if [ "$off" != "$kinds_before" ] && [ "$(setting_value dependencyKinds)" = "$kinds_before" ]; then flipped=$((flipped + 1)); fi
    done
    find_projects "Find again"
    if [ "$flipped" = "7" ] && [[ "$without_node" == *"rows=0 "* && "$(review_state projects)" == *"rows=2 checked=1 "* ]]; then pass "settings Project clean-up kind switches turn each kind off and on (Node modules off finds nothing)"; else fail "settings kind switches" "flipped $flipped, $without_node"; fi

    # Each cache switch hides its row and shows it again.
    flipped=0
    for title in "uv cache" "Bun cache" "Go modules" "Maven repository" "Hugging Face models" "pre-commit environments" "Editor caches" "Playwright browsers"; do
        press_now settings "$title" >/dev/null
        wait_for 5 setting_differs hiddenCacheRows ""
        hidden=$(setting_value hiddenCacheRows)
        press_now settings "$title" >/dev/null
        wait_for_value 5 "" setting_value hiddenCacheRows
        if [ -n "$hidden" ] && [ -z "$(setting_value hiddenCacheRows)" ]; then flipped=$((flipped + 1)); fi
    done
    if [ "$flipped" = "8" ]; then pass "settings Project clean-up cache switches hide each cache row and show it again"; else fail "settings cache switches" "flipped $flipped"; fi

    # Remove stops searching the folder; Add takes a folder inside the home folder and refuses
    # one outside it with a note (what the folder panel hands it, without the panel).
    press_in settings "Remove ~/Projects" >/dev/null
    roots_removed=$(setting_value projectRoots)
    outside=$($R "space-add-root:/private/tmp" 10)
    inside=$($R "space-add-root:$HOME/Projects" 10)
    if [ -z "$roots_removed" ] && [[ "$outside" == "added=false roots= note=Choose a folder inside your home folder, not in Library" && "$inside" == "added=true roots=Projects note=" ]]; then pass "settings \"Remove ~/…\" and \"Add folder…\" change the project folders, a folder outside home is refused with a note"; else fail "settings project folders" "$roots_removed / $outside / $inside"; fi
    $R close-windows 10 >/dev/null

    # The footer asks first; Cancel keeps the folder, the confirmation moves it to the made-up Trash.
    mkdir -p "$fake_home/.TestTrash"
    echo theirs > "$fake_home/.TestTrash/theirs.txt"
    find_projects "Find again"
    footer=$(review_controls | grep -E "^Move 1 folder, .+ to the Trash$" | head -1)
    press_in space "$footer" >/dev/null
    asked=$(review_state projects)
    # While it asks, the ticks stay as they are: the checkbox and Select none do nothing.
    fresh_box=$(review_controls | grep "/fresh-app/node_modules$" | head -1)
    press_in space "$fresh_box" >/dev/null
    press_in space "Select none" >/dev/null
    frozen=$(review_state projects)
    press_in space Cancel >/dev/null
    cancelled=$(review_state projects)
    if [ -n "$footer" ] && [[ "$asked" == *"confirming=true"* && "$cancelled" == *"confirming=false"* && "$cancelled" == *"exists=true"* ]]; then pass "Space review footer asks first and \"Cancel\" keeps the folders"; else fail "Space review Cancel" "$footer / $asked / $cancelled"; fi
    if [ -n "$fresh_box" ] && [[ "$asked" == *"checked=1 "* && "$frozen" == *"checked=1 "* && "$frozen" == *"confirming=true"* ]]; then pass "Space review ticks cannot change while the footer asks"; else fail "Space review frozen ticks" "$fresh_box / $asked / $frozen"; fi
    press_in space "$footer" >/dev/null
    press_in space "$footer" >/dev/null
    wait_review projects
    moved=$(review_state projects)
    if [[ "$moved" == *"trash=node_modules,theirs.txt "* && "$moved" == *"exists=false fresh=true"* && "$moved" == *"rows=1 "* ]]; then pass "Space review confirmation moves the ticked folder to the Trash and keeps the fresh one"; else fail "Space review move" "$moved"; fi
    for_good=$(review_controls | grep -E "^Delete this folder for good, .+" | head -1)
    press_in space "$for_good" >/dev/null
    wait_for_text 10 "askingForGood=true" $R space-review-state:projects 10
    asked_for_good=$(review_state projects)
    asked_text=$(review_controls | grep -cE "^Delete this folder, .+ for good\? This cannot be undone\.$")
    press_in space Cancel >/dev/null
    kept_for_good=$(review_state projects)
    press_in space "$for_good" >/dev/null
    press_in space "$for_good" >/dev/null
    wait_review projects
    if [ -n "$for_good" ] && [[ "$asked_for_good" == *"trash=node_modules,theirs.txt "* && "$asked_for_good" == *"askingForGood=true"* && "$kept_for_good" == *"trash=node_modules,theirs.txt "* && "$kept_for_good" == *"askingForGood=false"* && "$kept_for_good" == *"forGood=1"* ]] && [[ "$(review_state projects)" == *"trash=theirs.txt "* ]]; then pass "Space review \"Delete this folder for good\" asks first and deletes only what it moved"; else fail "Space review for good" "$for_good / asked $asked_text: $asked_for_good / $kept_for_good / $(review_state projects)"; fi
    press_in space "All categories" >/dev/null
    if review_controls | grep -qx "Review Project folders"; then pass "Space review \"All categories\" goes back, the Projects row offers \"Review Project folders\""; else fail "Space review back" "$(review_controls | tr '\n' ' ')"; fi
    press_in space "Review Project folders" >/dev/null
    if review_controls | grep -qx "Find again"; then pass "Space \"Review Project folders\" opens the last search"; else fail "Space Review Project folders"; fi

    # App caches: a row per cache folder, all ticked; removing deletes them, Library/Caches stays.
    press_in space "All categories" >/dev/null
    press_in space "Review App caches" >/dev/null
    wait_for_text 10 "rows=2" $R space-review-state:appCaches 10
    wait_review appCaches
    listed=$(review_state appCaches)
    footer=$(review_controls | grep -E "^Delete 2 items, " | head -1)
    press_in space "$footer" >/dev/null
    press_in space "$footer" >/dev/null
    wait_review appCaches
    if [[ "$listed" == *"rows=2 checked=2 "* ]] && [ -n "$footer" ] && [ ! -e "$fake_home/Library/Caches/com.example.app" ] && [ ! -e "$fake_home/Library/Caches/com.example.second" ] && [ -d "$fake_home/Library/Caches" ]; then pass "Space \"Review App caches\" lists each cache folder ticked, \"Delete …\" deletes them and keeps Library/Caches"; else fail "Space review App caches" "$listed / $footer / $(ls "$fake_home/Library/Caches")"; fi
    $R system-actions:stop 10 >/dev/null
fi
$R close-windows 10 >/dev/null
$R space-fake-home:off 60 >/dev/null
trap - INT TERM
if declare -F restore_running_app >/dev/null; then trap restore_running_app EXIT; else trap - EXIT; fi
settings_after="$(setting_value projectRoots)/$(setting_value oldProjectDays)/$(setting_value projectFoldersToTrash)/$(setting_value dependencyKinds)/$(setting_value hiddenCacheRows)"
# Without the made-up home the automation does not press a button that removes.
refused_press=$($R "press:space:Move 1 folder, 5 MB to the Trash" 10)
if [ "$settings_after" = "$settings_before" ] && [[ "$(review_state projects)" == refused* && "$refused_press" == refused* ]]; then pass "space-fake-home:off puts the project settings back and review commands refuse the real home"; else fail "space-fake-home:off restores" "$settings_before → $settings_after, press: $refused_press"; fi

section "toolbox buttons"
# Every tool gets an input typed into its fields; results are read from its Output and from what
# its Copy buttons put on the clipboard. Saved time zones are put back at the end.
# toolbox-open, set-value and press answer only after the app's moment for redrawing, and a tool
# computes its output as the field changes, so the next read sees the new output.
tb_open() { $R "toolbox-open:$1" 10 >/dev/null; }
tb_set() { $R "set-value:toolbox:$1=$2" 10 >/dev/null; }
tb_value() { local shown; shown=$($R "control-value:toolbox:$1" 10); echo "${shown#value=}"; }
tb_press() { press_in toolbox "$1" >/dev/null; }
tb_controls() { $R controls:toolbox 30 | sed 's/ ;; /\n/g'; }
# Something other than the sentinel is on the clipboard (empty is the moment between clearing and writing).
clipboard_has_copy() { local text; text=$(pbpaste); [ -n "$text" ] && [ "$text" != "clipboard-sentinel" ]; }
# tb_copies <label>: presses a copy button and prints what it put on the clipboard (nothing when it put
# nothing). The press answers at once and the clipboard is waited for; a button that copies nothing
# leaves the sentinel, and the wait ends at its timeout.
tb_copies() {
    printf 'clipboard-sentinel' | pbcopy
    press_now toolbox "$1" >/dev/null
    wait_for 2 clipboard_has_copy
    local text
    text=$(pbpaste)
    if [ "$text" != "clipboard-sentinel" ]; then printf '%s' "$text"; fi
}
toolbox_listing="$WORK/toolbox-controls.txt"
: > "$toolbox_listing"
# tb_every_copy <tool>: every Copy button of the open tool puts something on the clipboard; the
# tool's controls go to the coverage listing.
tb_every_copy() {
    local label copied controls empty=""
    # A Copy button without its own name is listed as "Copied" for 1.2 s after a press.
    wait_for_no_text 3 "|Copied" tb_controls
    controls=$(tb_controls)
    echo "$controls" >> "$toolbox_listing"
    while IFS= read -r label; do
        copied=$(tb_copies "$label")
        if [ -z "$copied" ]; then empty="$empty \"$label\""; fi
    done < <(echo "$controls" | cut -d'|' -f2- | grep -E "^Copy" | grep -vxF "Copy as…")
    if [ -z "$empty" ]; then pass "toolbox $1: every Copy button copies"; else fail "toolbox $1 Copy buttons" "$empty"; fi
}
saved_zones=$($R time-zones 10)

# Sidebar rows open their tool; search narrows the list; Paste & detect picks the tool.
tb_open JSON
# JSON is open already: it comes last, so every row's wait starts from another tool.
TOOLS=("XML" "YAML" "HTML" "SQL" "GraphQL" "JWT" "Base64" "URL encode" "HTML entities" "Time & dates" "Time zones" "JSON ↔ YAML ↔ XML ↔ CSV" "Numbers, colors, case" "UUID · hash" "Test data" "QR code" "Regex" "JSON diff" "JSONPath" "HTTP message" "Cron" "String length" "Color & contrast" "JSON")
wrong=""
for tool in "${TOOLS[@]}"; do
    press_now toolbox "$tool" >/dev/null
    wait_for_value 5 "tool=$tool" $R toolbox-tool 10
    if [ "$($R toolbox-tool 10)" != "tool=$tool" ]; then wrong="$wrong \"$tool\""; fi
done
if [ -z "$wrong" ]; then pass "toolbox sidebar row opens its tool (${#TOOLS[@]} tools)"; else fail "toolbox sidebar rows" "$wrong"; fi
tb_set "Search tools" "cron"
rows=$(tb_controls)
tb_set "Search tools" ""
if [[ "$rows" == *"|Cron"* && "$rows" != *"|JSON diff"* && "$(tb_controls)" == *"|JSON diff"* ]]; then pass "toolbox \"Search tools\" narrows the list and clearing it shows all"; else fail "toolbox search"; fi
jwt_payload=$(printf '{"sub":"42","name":"Bear"}' | base64 | tr '+/' '-_' | tr -d '=')
jwt="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.$jwt_payload.c2ln"
printf '%s' "$jwt" | pbcopy
tb_press "Paste & detect"
if [ "$($R toolbox-tool 10)" = "tool=JWT" ] && [ "$(tb_value Input)" = "$jwt" ]; then pass "toolbox \"Paste & detect\" opens the tool that fits the clipboard"; else fail "toolbox Paste & detect" "$($R toolbox-tool 10)"; fi

# JSON formatter: Format and Minify, indent, sorted keys, nested JSON, Copy as, Clear.
tb_open JSON
tb_set Input '{"b":1,"a":{"c":"x"}}'
formatted=$(tb_value Output)
tb_press Minify
minified=$(tb_value Output)
tb_press Format
if [[ "$formatted" == *'\n  "'* && "$minified" != *'\n'* && "$(tb_value Output)" == "$formatted" ]]; then pass "toolbox JSON \"Format\" and \"Minify\""; else fail "toolbox JSON Format/Minify" "$formatted / $minified"; fi
$R "choose:toolbox:Indent => 4 spaces" 10 >/dev/null
four=$(tb_value Output)
$R "choose:toolbox:Indent => Tabs" 10 >/dev/null
tabs=$(tb_value Output)
$R "choose:toolbox:Indent => 2 spaces" 10 >/dev/null
if [[ "$four" == *'\n    "'* && "$tabs" == *$'\t'* && "$(tb_value Output)" == "$formatted" ]]; then pass "toolbox JSON \"Indent\" picks 4 spaces, tabs and back"; else fail "toolbox JSON Indent" "$four / $tabs"; fi
tb_press "Sort keys"
sorted=$(tb_value Output)
tb_press "Sort keys"
if [[ "$sorted" == '{\n  "a"'* && "$(tb_value Output)" == '{\n  "b"'* ]]; then pass "toolbox JSON \"Sort keys\" sorts and unsorts"; else fail "toolbox JSON Sort keys" "$sorted"; fi
tb_set Input '{"s":"{\"n\":1}"}'
tb_press "Unescape nested JSON strings"
unescaped=$(tb_value Output)
tb_press "Unescape nested JSON strings"
if [[ "$unescaped" == *'"n"'* && "$unescaped" != *'\"n'* && "$(tb_value Output)" == *'\"n'* ]]; then pass "toolbox JSON \"Unescape nested JSON strings\" expands nested JSON"; else fail "toolbox JSON unescape" "$unescaped"; fi
tb_set Input '{"b":1}'
copied_as=""
for item in "Copy as YAML|b: 1" "Copy as XML|<b>1</b>" "Copy as CSV|b"; do
    printf 'clipboard-sentinel' | pbcopy
    $R "choose:toolbox:Copy as… => ${item%%|*}" 10 >/dev/null
    if ! pbpaste | grep -qF "${item##*|}"; then copied_as="$copied_as ${item%%|*}: $(pbpaste | head -1)"; fi
done
if [ -z "$copied_as" ]; then pass "toolbox JSON \"Copy as…\" copies YAML, XML and CSV"; else fail "toolbox JSON Copy as" "$copied_as"; fi
tb_every_copy JSON
tb_press Clear
if [ -z "$(tb_value Input)" ]; then pass "toolbox formatter \"Clear\" empties the input"; else fail "toolbox Clear" "$(tb_value Input)"; fi

# The other formatters: Format and Minify give different text.
for row in 'XML|<a><b>1</b></a>' 'YAML|b: 1\na:\n  c: 2' 'HTML|<div><p>Hi</p></div>' 'SQL|select a, b from t where a = 1' 'GraphQL|{ user(id: 1) { name } }'; do
    tool="${row%%|*}"
    tb_open "$tool"
    tb_set Input "${row#*|}"
    formatted=$(tb_value Output)
    tb_press Minify
    minified=$(tb_value Output)
    tb_press Format
    if [ -n "$formatted" ] && [ "$formatted" != "$minified" ] && [ "$(tb_value Output)" = "$formatted" ]; then pass "toolbox $tool \"Format\" and \"Minify\""; else fail "toolbox $tool Format/Minify" "$formatted / $minified"; fi
    tb_every_copy "$tool"
done
tb_open YAML
tb_set Input 'b: 1\na: 2'
tb_press "Sort keys"
sorted=$(tb_value Output)
tb_press "Sort keys"
if [[ "$sorted" == a:* ]]; then pass "toolbox YAML \"Sort keys\" sorts"; else fail "toolbox YAML Sort keys" "$sorted"; fi

# Data converter: source and target formats, swap.
tb_open "JSON ↔ YAML ↔ XML ↔ CSV"
tb_set Input '[{"a":1,"b":"x"}]'
# The source picker starts on JSON; "#last" is the target picker (the sidebar has a JSON row too).
tb_press "YAML#last"
as_yaml=$(tb_value Output)
tb_press "XML#last"
as_xml=$(tb_value Output)
tb_press "CSV#last"
as_csv=$(tb_value Output)
if [[ "$as_yaml" == *"a: 1"* && "$as_xml" == *"<"* && "$as_csv" == *"a,b"* ]]; then pass "toolbox converter turns JSON into YAML, XML and CSV"; else fail "toolbox converter" "$as_yaml / $as_xml / $as_csv"; fi
tb_every_copy "converter"
tb_press "Swap formats"
if [[ "$(tb_value Input)" == *"a,b"* && "$(tb_value Output)" == *'"a"'* ]]; then pass "toolbox converter \"Swap formats\" turns the output into the input"; else fail "toolbox converter swap" "$(tb_value Input)"; fi

# Codecs: Encode, Decode, options and Swap.
tb_open Base64
tb_set Input 'hello?>'
tb_press Encode
encoded=$(tb_value Output)
tb_press "URL-safe alphabet (encode)"
url_safe=$(tb_value Output)
tb_press "URL-safe alphabet (encode)"
tb_every_copy Base64
tb_press Swap
if [ "$encoded" = "aGVsbG8/Pg==" ] && [[ "$url_safe" == *"_"* && "$url_safe" != *"/"* ]] && [ "$(tb_value Output)" = "hello?>" ]; then pass "toolbox Base64 \"Encode\", URL-safe and \"Swap\" back to \"Decode\""; else fail "toolbox Base64" "$encoded / $url_safe / $(tb_value Output)"; fi
tb_open "URL encode"
tb_set Input 'a b&c'
tb_press Encode
component=$(tb_value Output)
tb_press "Encode as a query component (also / ? & =)"
whole=$(tb_value Output)
tb_press "Encode as a query component (also / ? & =)"
tb_every_copy "URL encode"
tb_press Decode
tb_set Input 'https://x.test/?q=1&r=two'
printf 'clipboard-sentinel' | pbcopy
$R "choose:toolbox:Query parameters (2) => r = two" 10 >/dev/null
if [ "$component" = "a%20b%26c" ] && [[ "$whole" == *"&"* ]] && [ "$(pbpaste)" = "two" ]; then pass "toolbox URL \"Encode\", query component switch and \"Query parameters\" copy a value"; else fail "toolbox URL" "$component / $whole / $(pbpaste)"; fi
tb_open "HTML entities"
tb_set Input '<ü>'
tb_press Encode
plain=$(tb_value Output)
tb_press "Encode non-ASCII as &#…;"
numeric=$(tb_value Output)
tb_press "Encode non-ASCII as &#…;"
tb_every_copy "HTML entities"
if [[ "$plain" == *"&lt;"* && "$plain" == *"ü"* && "$numeric" == *"&#"* ]]; then pass "toolbox HTML entities \"Encode\" and the non-ASCII switch"; else fail "toolbox entities" "$plain / $numeric"; fi
tb_open JWT
tb_set Input "$jwt"
header_copy=$(tb_copies "Copy header")
payload_copy=$(tb_copies "Copy payload")
if [[ "$(tb_value Header)" == *"HS256"* && "$header_copy" == *"HS256"* && "$payload_copy" == *"Bear"* ]]; then pass "toolbox JWT shows and copies the header and payload"; else fail "toolbox JWT" "$header_copy / $payload_copy"; fi
tb_every_copy JWT

# Time: Now, zone cards from "Add zone", Remove, and "Search all zones & compare…".
tb_open "Time & dates"
tb_press Now
now_value=$(tb_value "1792839492, 2026-10-24T10:58:12Z, in 3 days…")
# Only a number is counted with: "not found" in arithmetic would stop the whole run.
if [[ "$now_value" =~ ^[0-9]+$ ]] && [ $(( $(date +%s) - now_value )) -lt 10 ]; then pass "toolbox Time \"Now\" puts in the current time"; else fail "toolbox Time Now" "$now_value"; fi
tb_every_copy "Time"
zone=$($R "menu-items:toolbox:Add zone" 10 | sed 's/ ;; /\n/g' | grep "/" | while IFS= read -r item; do [[ ",$saved_zones," == *",$item,"* ]] || { echo "$item"; break; }; done)
$R "choose:toolbox:Add zone => $zone" 10 >/dev/null
added=$($R time-zones 10)
city=$(echo "${zone##*/}" | tr '_' ' ')
tb_press "Remove $city"
if [ -n "$zone" ] && [[ ",$added," == *",$zone,"* && ",$($R time-zones 10)," != *",$zone,"* ]]; then pass "toolbox Time \"Add zone\" adds $zone and \"Remove $city\" takes it away"; else fail "toolbox Time zones" "$zone: $added"; fi
$R "choose:toolbox:Add zone => Search all zones & compare…" 10 >/dev/null
if [ "$($R toolbox-tool 10)" = "tool=Time zones" ]; then pass "toolbox Time \"Search all zones & compare…\" opens Time zones"; else fail "toolbox Time compare" "$($R toolbox-tool 10)"; fi

# Time zones: the slider and Now, search, add, clear, remove.
tb_open "Time zones"
tb_press "Compare at#increment"
moved=$(tb_value "Compare at")
tb_press Now
if [ "$moved" != "0" ] && [ -n "$moved" ] && [ "$(tb_value "Compare at")" = "0" ]; then pass "toolbox Time zones slider moves the time and \"Now\" brings it back"; else fail "toolbox Time zones slider" "$moved / $(tb_value "Compare at")"; fi
search_label="Search a city, country, abbreviation (PST) or offset (+5:30)"
tb_set "$search_label" "Kathmandu"
tb_press "Add Asia/Kathmandu"
added=$($R time-zones 10)
tb_press "Clear search"
cleared=$(tb_value "$search_label")
tb_every_copy "Time zones"
tb_press "Remove Kathmandu"
if [[ "$added" == *"Asia/Kathmandu"* && -z "$cleared" && "$($R time-zones 10)" != *"Asia/Kathmandu"* ]]; then pass "toolbox Time zones search adds a zone, \"Clear search\" and \"Remove\" work"; else fail "toolbox Time zones search" "$added / $cleared"; fi
$R "time-zones:set:$saved_zones" 10 >/dev/null

# Quick converters: each field converts what is typed into it.
tb_open "Numbers, colors, case"
tb_set "255, 0xFF, 0b1010" "0x10"
tb_set "#FF6B4A, rgb(…), hsl(…)" "#000000"
tb_set "any identifier or phrase" "order total"
tb_set "5242880, 5 MB, 1.5 GiB" "1 KiB"
tb_set "93784, PT26H3M4S, 1d 2h" "90"
if [ "$(tb_copies "Copy Decimal")" = "16" ] && [[ "$(tb_copies "Copy RGB")" == *"0, 0, 0"* ]] && [ "$(tb_copies "Copy camelCase")" = "orderTotal" ] && [ "$(tb_copies "Copy Seconds")" = "90" ]; then pass "toolbox quick converters convert what is typed"; else fail "toolbox quick converters" "$(tb_copies "Copy Decimal") $(tb_copies "Copy camelCase")"; fi
tb_every_copy "quick converters"

# UUIDs and hashes.
tb_open "UUID · hash"
first_batch=$(tb_copies "Copy all")
tb_press Generate
second_batch=$(tb_copies "Copy all")
tb_press v7
v7=$(tb_copies "Copy all" | head -1)
tb_press v4
tb_press Uppercase
upper=$(tb_copies "Copy all" | head -1)
tb_press Uppercase
tb_press "$(tb_controls | cut -d'|' -f2- | grep -E "^Count: " | head -1)#increment"
six=$(tb_copies "Copy all" | grep -c .)
tb_press "$(tb_controls | cut -d'|' -f2- | grep -E "^Count: " | head -1)#decrement"
if [ "$first_batch" != "$second_batch" ] && [ "${v7:14:1}" = "7" ] && [ "$upper" = "$(echo "$upper" | tr '[:lower:]' '[:upper:]')" ] && [ "$six" = "6" ]; then pass "toolbox UUID \"Generate\", v7, \"Uppercase\" and the count"; else fail "toolbox UUID" "v7=$v7 upper=$upper lines=$six"; fi
tb_set Input "abc"
if [ "$(tb_copies "Copy MD5")" = "900150983cd24fb0d6963f7d28e17f72" ]; then pass "toolbox hash of text (MD5 of abc)"; else fail "toolbox hash" "$(tb_copies "Copy MD5")"; fi
tb_every_copy "UUID · hash"

# Test data: every Generate gives new values, pickers, password rules, the checker.
tb_open "Test data"
people=$(tb_copies "Copy all")
tb_press UK
uk_people=$(tb_copies "Copy all")
tb_press "Generate people"
if [ "$people" != "$uk_people" ] && [ "$uk_people" != "$(tb_copies "Copy all")" ]; then pass "toolbox test data people: country and \"Generate people\""; else fail "toolbox test data people"; fi
tb_press Amex
amex=$(tb_copies "Copy Number · passes Luhn")
tb_press "Generate card"
if [[ "$amex" == 3* && "$amex" != "$(tb_copies "Copy Number · passes Luhn")" ]]; then pass "toolbox test data card: brand and \"Generate card\""; else fail "toolbox test data card" "$amex"; fi
tb_press "NL"
nl=$(tb_copies "Copy Valid check digits")
tb_press "Generate IBAN"
if [[ "$nl" == NL* && "$nl" != "$(tb_copies "Copy Valid check digits")" ]]; then pass "toolbox test data IBAN: country and \"Generate IBAN\""; else fail "toolbox test data IBAN" "$nl"; fi
tb_press "Length: 16#increment"
tb_press "0-9"
password_label=$(tb_controls | cut -d'|' -f2- | grep -E "^Copy [0-9]+ characters$" | head -1)
password=$(tb_copies "$password_label")
tb_press "0-9"
tb_press "Length: 17#decrement"
tb_press "Generate passwords"
if [ "$password_label" = "Copy 17 characters" ] && [[ "$password" != *[[:digit:]]* ]]; then pass "toolbox test data passwords: length, \"0-9\" and \"Generate passwords\""; else fail "toolbox test data passwords" "$password_label $password"; fi
tb_set "Paste a card number or IBAN" "4111111111111111"
if [ "$(tb_value "Paste a card number or IBAN")" = "4111111111111111" ]; then pass "toolbox test data checker takes a card number"; else fail "toolbox test data checker"; fi
# Every country and brand gives its own values; DE and PL also exist for IBANs, "#last" is the IBAN one.
not_changing=""
for pill in US DE BY PL; do
    before=$(tb_copies "Copy all")
    tb_press "$pill"
    if [ "$before" = "$(tb_copies "Copy all")" ]; then not_changing="$not_changing $pill"; fi
done
for pill in Visa Mastercard Mir; do
    before=$(tb_copies "Copy Number · passes Luhn")
    tb_press "$pill"
    if [ "$before" = "$(tb_copies "Copy Number · passes Luhn")" ]; then not_changing="$not_changing $pill"; fi
done
for pill in "DE#last|DE" "GB|GB" "PL#last|PL"; do
    tb_press "${pill%%|*}"
    if [[ "$(tb_copies "Copy Valid check digits")" != "${pill##*|}"* ]]; then not_changing="$not_changing IBAN ${pill##*|}"; fi
done
if [ -z "$not_changing" ]; then pass "toolbox test data countries and card brands each give their own values"; else fail "toolbox test data pickers" "$not_changing"; fi
password_label=$(tb_controls | cut -d'|' -f2- | grep -E "^Copy [0-9]+ characters$" | head -1)
tb_press "A-Z"
tb_press "!@#"
plain_password=$(tb_copies "$password_label")
tb_press "A-Z"
tb_press "!@#"
if [[ "$plain_password" != *[[:upper:]]* && "$plain_password" =~ ^[[:lower:][:digit:]]+$ ]]; then pass "toolbox test data \"A-Z\" and \"!@#\" switch letters and symbols"; else fail "toolbox test data A-Z/!@#" "$plain_password"; fi
tb_every_copy "Test data"

# Regex: pattern, flags, replace, Paste.
tb_open Regex
printf 'Fixed qa-1 and QA-22' | pbcopy
tb_press Paste
tb_set Pattern 'QA-(\d+)'
matches_case=$(tb_controls | grep -c "|Copy Match ")
tb_press i
matches_any=$(tb_controls | grep -c "|Copy Match ")
tb_press i
# '[$1]' is the regex template itself, not a shell variable.
# shellcheck disable=SC2016
tb_set "Template, e.g. [\$1] or \${id}" '[$1]'
replaced=$(tb_copies "Copy After replace")
tb_every_copy Regex
if [ "$(tb_value Input)" = "Fixed qa-1 and QA-22" ] && [ "$matches_case" = 1 ] && [ "$matches_any" = 2 ] && [ "$replaced" = "Fixed qa-1 and [22]" ]; then pass "toolbox Regex \"Paste\", pattern, \"i\" and replace"; else fail "toolbox Regex" "$matches_case $matches_any $replaced"; fi
tb_press m
tb_press s
tb_press m
tb_press s
pass "toolbox Regex \"m\" and \"s\" switch without errors"

# QR: Copy image, read it back, Save PNG…, Read from screen… (cancelled).
tb_open "QR code"
tb_set Input "https://example.test/qr"
tb_press "Copy image"
image_types=$($R pasteboard-types 10)
tb_set Input "x"
tb_press "Read from clipboard image"
wait_for_value 10 "https://example.test/qr" tb_value Input
read_back=$(tb_value Input)
$R system-actions:start 10 >/dev/null
rm -f "$WORK/qr.png"
$R "system-actions:files:$WORK/qr.png" 10 >/dev/null
tb_press "Save PNG…"
wait_for 10 test -s "$WORK/qr.png"
$R system-actions:stop 10 >/dev/null
if [[ "$image_types" == *png* || "$image_types" == *tiff* ]] && [ "$read_back" = "https://example.test/qr" ]; then pass "toolbox QR \"Copy image\" and \"Read from clipboard image\" round trip"; else fail "toolbox QR copy and read" "$image_types / $read_back"; fi
if file "$WORK/qr.png" 2>/dev/null | grep -q PNG; then pass "toolbox QR \"Save PNG…\" writes the code"; else fail "toolbox QR save"; fi
tb_press "Read from screen…"
wait_for 10 pgrep -x screencapture
if pgrep -x screencapture >/dev/null; then picking=true; else picking=false; fi
pkill -x screencapture 2>/dev/null
if [ "$picking" = true ]; then pass "toolbox QR \"Read from screen…\" starts picking an area"; else fail "toolbox QR read from screen"; fi

# JSON diff, JSONPath, HTTP, Cron, String length.
tb_open "JSON diff"
printf '{"a":1}' | pbcopy
tb_press "Paste before"
tb_set After '{"a":2,"b":3}'
changes=$(tb_copies "Copy list")
if [ "$(tb_value Before)" = '{"a":1}' ] && [[ "$changes" == *a* && "$changes" == *b* ]]; then pass "toolbox JSON diff \"Paste before\" and \"Copy list\" of what changed"; else fail "toolbox JSON diff" "$changes"; fi
printf '{"a":2}' | pbcopy
tb_press "Paste after"
if [ "$(tb_value After)" = '{"a":2}' ]; then pass "toolbox JSON diff \"Paste after\""; else fail "toolbox JSON diff paste after"; fi
tb_every_copy "JSON diff"
tb_open JSONPath
tb_set Input '{"items":[{"id":1},{"id":2}]}'
examples_ok=true
# The first example may be in the field already: it comes last, so every wait starts from another one.
for example in '$.items[*]' '$.items[0]' '$..*' '$..id'; do
    press_now toolbox "$example" >/dev/null
    wait_for_value 5 "$example" tb_value '$.items[*].price'
    if [ "$(tb_value '$.items[*].price')" != "$example" ]; then examples_ok=false; fi
done
tb_press '$..id'
values=$(tb_copies "Copy values")
printf '{"z":5}' | pbcopy
tb_press Paste
if [ "$examples_ok" = true ] && [ "$values" = $'1\n2' ] && [ "$(tb_value Input)" = '{"z":5}' ]; then pass "toolbox JSONPath examples, \"Copy values\" and \"Paste\""; else fail "toolbox JSONPath" "$examples_ok $values"; fi
# Something to copy: the pasted document has no ids.
tb_set Input '{"items":[{"id":1},{"id":2}]}'
tb_every_copy JSONPath
tb_open "HTTP message"
printf 'GET /a?x=1 HTTP/1.1\nHost: t.test\nCookie: s=2\n\n' | pbcopy
tb_press Paste
if [[ "$(tb_value Input)" == "GET /a?x=1"* ]]; then pass "toolbox HTTP \"Paste\" takes the message"; else fail "toolbox HTTP paste"; fi
tb_every_copy HTTP
tb_open Cron
examples_ok=true
# The first example may be in the field already: it comes last, so every wait starts from another one.
for example in "0 9 * * 1-5" "30 2 * * 0" "0 0 1 * *" "@hourly" "0 */6 * * *" "*/5 * * * *"; do
    press_now toolbox "$example" >/dev/null
    wait_for_value 5 "$example" tb_value "minute hour day month weekday"
    if [ "$(tb_value "minute hour day month weekday")" != "$example" ]; then examples_ok=false; fi
done
if [ "$examples_ok" = true ]; then pass "toolbox Cron example buttons fill the expression"; else fail "toolbox Cron examples"; fi
tb_every_copy Cron
tb_open "String length"
tb_press 255
made=$(tb_copies "Copy string")
tb_press "Change length#increment"
longer=$(tb_value Length)
styles=""
for style in "a a a" Cyrillic Emoji; do
    tb_press "$style"
    styles="$styles|$(tb_copies "Copy string" | head -c 12)"
done
emoji=$(tb_copies "Copy string")
tb_press Counterstring
tb_set Input "héllo"
if [ "${#made}" = 255 ] && [ "$longer" = 256 ] && [ "$emoji" != "$made" ] && [ "$(echo "$styles" | tr '|' '\n' | sort -u | grep -c .)" = 3 ] && [ "$(tb_copies "Copy Characters#last")" = 5 ] && [ "$(tb_copies "Copy UTF-8 bytes#last")" = 6 ]; then pass "toolbox String length presets, stepper, styles and counts"; else fail "toolbox String length" "${#made} $longer"; fi
tb_every_copy "String length"

# Color & contrast: typed colors, Swap colors, the eyedropper (Esc cancels).
tb_open "Color & contrast"
tb_set "Text color" "#000000"
# Still typing in the background field when Swap is pressed: the field must not keep its old text.
$R 'set-value-typing:toolbox:Background color=#FFFFFF' 10 >/dev/null
tb_press "Swap colors"
if [ "$(tb_value "Text color")" = "#FFFFFF" ] && [ "$(tb_value "Background color")" = "#000000" ]; then pass "toolbox contrast \"Swap colors\""; else fail "toolbox contrast swap"; fi
tb_press "Pick the text color"
wait_for_text 10 "picking=true" tools_now
picking=$(tools_now)
$R post-key:53:none 10 >/dev/null
wait_for_text 10 "picking=false" tools_now
tb_press "Pick the background color"
wait_for_text 10 "picking=true" tools_now
picking_back=$(tools_now)
$R post-key:53:none 10 >/dev/null
wait_for_text 10 "picking=false" tools_now
if [[ "$picking" == *"picking=true"* && "$picking_back" == *"picking=true"* && "$(tools_now)" == *"picking=false"* ]]; then pass "toolbox contrast eyedroppers open the color loupe, Esc closes it"; else fail "toolbox contrast eyedroppers" "$picking"; fi
tb_controls >> "$toolbox_listing"
$R close-windows 10 >/dev/null

section "welcome guide buttons"
# Every page of the guide; each choice is put back the way the person had it.
saved_minutes=$(setting_value bufferMinutes)
saved_buffer_on=$(setting_value startBufferOnLaunch)
saved_crash=$(setting_value saveOnCrash)
saved_crash_days=$(setting_value keepCrashClipsDays)
saved_typed=$(setting_value recordTypedText)
saved_guide_page=$(defaults read "$BUNDLE_ID" onboardingPage 2>/dev/null || echo "")
defaults delete "$BUNDLE_ID" onboardingPage 2>/dev/null
$R close-windows 10 >/dev/null
$R open-onboarding 10 >/dev/null
$R system-actions:start 10 >/dev/null
guide_page() { setting_value onboardingPage; }
onboarding_controls=$($R controls:onboarding 30 | sed 's/ ;; /\n/g' | sed "s#^#onboarding|#")
press_in onboarding Continue >/dev/null
first_continue=$(guide_page)
press_in onboarding Back >/dev/null
back_page=$(guide_page)
press_in onboarding Continue >/dev/null
if [ "$first_continue" = 1 ] && [ "$back_page" = 0 ] && [ "$(guide_page)" = 1 ]; then pass "guide \"Continue\" and \"Back\" move between pages"; else fail "guide Continue/Back" "$first_continue $back_page"; fi
onboarding_controls="$onboarding_controls"$'\n'"$($R controls:onboarding 30 | sed 's/ ;; /\n/g' | sed "s#^#onboarding|#")"
press_in onboarding "Off for now" >/dev/null
off=$(setting_value startBufferOnLaunch)
press_in onboarding "Keep the last minutes" >/dev/null
on=$(setting_value startBufferOnLaunch)
other_minutes=2
if [ "$saved_minutes" = 2 ]; then other_minutes=3; fi
press_in onboarding "$other_minutes min" >/dev/null
picked_minutes=$(setting_value bufferMinutes)
press_in onboarding "$saved_minutes min" >/dev/null
if [ "$saved_buffer_on" != 1 ]; then press_in onboarding "Off for now" >/dev/null; fi
if [ "$off" = 0 ] && [ "$on" = 1 ] && [ "$picked_minutes" = "$other_minutes" ] && [ "$(setting_value bufferMinutes)" = "$saved_minutes" ]; then pass "guide buffer choices \"Off for now\", \"Keep the last minutes\" and the minutes"; else fail "guide buffer choices" "$off $on $picked_minutes"; fi
if [[ "$($R controls:onboarding 30)" == *"Keep all"* ]]; then
    first=$(setting_value captureAllDisplays)
    press_in onboarding "$($R controls:onboarding 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep "^Keep all" | head -1)" >/dev/null
    second=$(setting_value captureAllDisplays)
    press_in onboarding "$($R controls:onboarding 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep "^Keep all" | head -1)" >/dev/null
    if [ "$first" != "$second" ]; then pass "guide \"Keep all screens\" switch"; else fail "guide all screens switch"; fi
fi
press_in onboarding Continue >/dev/null
onboarding_controls="$onboarding_controls"$'\n'"$($R controls:onboarding 30 | sed 's/ ;; /\n/g' | sed "s#^#onboarding|#")"
press_in onboarding "Choose…" >/dev/null
if [[ "$($R system-actions:read 10)" == *"choose folder"* ]]; then pass "guide \"Choose…\" asks for the save folder"; else fail "guide Choose…" "$($R system-actions:read 10)"; fi
if [ "$saved_crash" != 1 ]; then press_in onboarding "Save the minute before an app crashes" >/dev/null; fi
other_days="30 days"
if [ "$saved_crash_days" = 30 ]; then other_days="3 days"; fi
press_in onboarding "$other_days" >/dev/null
picked_days=$(setting_value keepCrashClipsDays)
if [ "$saved_crash_days" = 0 ]; then press_in onboarding "Always" >/dev/null; else press_in onboarding "$saved_crash_days days" >/dev/null; fi
press_in onboarding "Save the minute before an app crashes" >/dev/null
crash_flipped=$(setting_value saveOnCrash)
press_in onboarding "Save the minute before an app crashes" >/dev/null
if [ "$picked_days" = "${other_days%% *}" ] && [ "$crash_flipped" != "$(setting_value saveOnCrash)" ] && [ "$(setting_value keepCrashClipsDays)" = "$saved_crash_days" ]; then pass "guide crash clips switch and how long they stay"; else fail "guide crash clips" "$picked_days $crash_flipped"; fi
if [ "$saved_crash" != 1 ]; then press_in onboarding "Save the minute before an app crashes" >/dev/null; fi
press_in onboarding Continue >/dev/null
onboarding_controls="$onboarding_controls"$'\n'"$($R controls:onboarding 30 | sed 's/ ;; /\n/g' | sed "s#^#onboarding|#")"
# Each "Allow …" shown (a permission not given yet) asks macOS once, recorded instead of shown.
asked=0
unasked=""
for permission in "Screen & System Audio Recording" Accessibility Microphone Camera; do
    before_count=$($R system-actions:read 10 | sed 's/ ;; /\n/g' | grep -c .)
    if [ "$(press_in onboarding "Allow $permission")" != "pressed" ]; then continue; fi
    asked=$((asked + 1))
    if [ "$($R system-actions:read 10 | sed 's/ ;; /\n/g' | grep -c .)" -le "$before_count" ]; then unasked="$unasked \"$permission\""; fi
done
if [ -z "$unasked" ]; then pass "guide \"Allow …\" asks macOS for each permission not given yet ($asked shown)"; else fail "guide Allow" "$unasked"; fi
# "Relaunch" shows when Screen Recording is allowed but the buffer has not started yet.
$R buffer-needs-permission:on 10 >/dev/null
wait_for_text 10 Relaunch $R controls:onboarding 30
relaunch_result=$(press_in onboarding Relaunch)
onboarding_controls="$onboarding_controls"$'\n'"$($R controls:onboarding 30 | sed 's/ ;; /\n/g' | sed "s#^#onboarding|#")"
$R buffer-needs-permission:off 10 >/dev/null
if [ "$relaunch_result" = "pressed" ] && [[ "$($R system-actions:read 10)" == *"relaunch"* ]]; then pass "guide \"Relaunch\" restarts the app after Screen Recording is allowed"; else fail "guide Relaunch" "$relaunch_result $($R system-actions:read 10)"; fi
press_in onboarding "Show what I type in steps" >/dev/null
typed=$(setting_value recordTypedText)
press_in onboarding "Show what I type in steps" >/dev/null
if [ "$typed" != "$saved_typed" ] && [ "$(setting_value recordTypedText)" = "$saved_typed" ]; then pass "guide \"Show what I type in steps\" switch"; else fail "guide typed text" "$typed"; fi
press_in onboarding Continue >/dev/null
press_in onboarding Continue >/dev/null
onboarding_controls="$onboarding_controls"$'\n'"$($R controls:onboarding 30 | sed 's/ ;; /\n/g' | sed "s#^#onboarding|#")"
press_in onboarding "Start using $APP_NAME" >/dev/null
wait_for_no_text 10 onboarding windows_now
if [[ "$(windows_now)" != *"onboarding"* ]] && [ "$(setting_value onboardingCompleted)" = 1 ]; then pass "guide \"Start using $APP_NAME\" finishes the guide"; else fail "guide Start using $APP_NAME" "$(windows_now)"; fi
$R open-onboarding 10 >/dev/null
press_in onboarding Skip >/dev/null
wait_for_no_text 10 onboarding windows_now
if [[ "$(windows_now)" != *"onboarding"* ]]; then pass "guide \"Skip\" closes the guide"; else fail "guide Skip"; fi
$R system-actions:stop 10 >/dev/null
if [ -n "$saved_guide_page" ]; then defaults write "$BUNDLE_ID" onboardingPage -int "$saved_guide_page"; fi
echo "$onboarding_controls" > "$WORK/onboarding-controls.txt"

section "feedback window buttons"
$R system-actions:start 10 >/dev/null
$R open-feedback:problem:keep 10 >/dev/null
feedback_controls=$($R controls:feedback 30)
echo "$feedback_controls" | sed 's/ ;; /\n/g' | sed "s#^#feedback|#" > "$WORK/feedback-controls.txt"
press_in feedback "Suggest a feature" >/dev/null
idea_controls=$($R controls:feedback 30)
press_in feedback "Report a problem" >/dev/null
if [[ "$feedback_controls" == *"|Attach logs"* && "$idea_controls" != *"|Attach logs"* && "$($R controls:feedback 30)" == *"|Attach logs"* ]]; then pass "feedback \"Report a problem\" and \"Suggest a feature\" switch the form"; else fail "feedback kind" "$idea_controls"; fi
logs_before=$($R control-value:feedback:"Attach logs" 10)
press_in feedback "Attach logs" >/dev/null
logs_after=$($R control-value:feedback:"Attach logs" 10)
if [ "$logs_before" != "$logs_after" ]; then pass "feedback \"Attach logs\" switch"; else fail "feedback Attach logs" "$logs_before"; fi
if [ "$logs_after" = "value=1" ]; then press_in feedback "Attach logs" >/dev/null; fi
preview_before=$($R control-value:feedback:"What will be sent" 10)
press_in feedback "What will be sent" >/dev/null
preview_after=$($R control-value:feedback:"What will be sent" 10)
if [ "$preview_before" != "$preview_after" ]; then pass "feedback \"What will be sent\" opens the preview"; else fail "feedback preview" "$preview_before"; fi
$R "set-value:feedback:Title=Buttons test title" 10 >/dev/null
$R "set-value:feedback:Details=Typed by the e2e test" 10 >/dev/null
press_in feedback "Open on GitHub" >/dev/null
wait_for_text 10 "open https://github.com/" $R system-actions:read 10
opened=$($R system-actions:read 10)
if [[ "$opened" == *"open https://github.com/"*"Buttons"*"test"*"title"* ]]; then pass "feedback title and details are typed, \"Open on GitHub\" opens the filled form"; else fail "feedback Open on GitHub" "$opened"; fi
$R open-feedback:problem:keep 10 >/dev/null
press_in feedback Cancel >/dev/null
wait_for_no_text 10 feedback windows_now
if [[ "$(windows_now)" != *"feedback"* ]]; then pass "feedback \"Cancel\" closes the window"; else fail "feedback Cancel"; fi
$R system-actions:stop 10 >/dev/null

section "update badge buttons"
$R system-actions:start 10 >/dev/null
$R update-fake:available 10 >/dev/null
$R close-panel 10 >/dev/null
$R press-status-item 10 >/dev/null
press_in menubar "Update to 9.9.9" >/dev/null
wait_for_text 10 "Update now" $R controls:popover 30
popover_controls=$($R controls:popover 30)
echo "$popover_controls" | sed 's/ ;; /\n/g' | sed "s#^#update|#" > "$WORK/update-controls.txt"
press_in popover "#42 Fake change for tests" >/dev/null
link=$($R system-actions:read 10)
press_in popover "Another fake change" >/dev/null
commit_link=$($R system-actions:read 10)
press_in popover Later >/dev/null
wait_for_no_text 10 "|Later" $R controls:popover 30
later=$($R controls:popover 30)
press_in menubar "Update to 9.9.9" >/dev/null
wait_for_text 10 "Update now" $R controls:popover 30
press_in popover "Update now" >/dev/null
# Real time: the update starts; its result is read at the end of the section.
sleep 0.5
if [[ "$popover_controls" == *"|Update now"* && "$link" == *"open https://github.com/"*"/pull/42"* && "$later" != *"|Later"* ]]; then pass "update badge opens the changes, a change links to its pull request, \"Later\" closes"; else fail "update badge details" "$link / $later"; fi
if [[ "$commit_link" == *"open https://github.com/"*"/commit/def5678"* ]]; then pass "update badge: a change without a pull request links to its commit"; else fail "update badge commit link" "$commit_link"; fi
if [[ "$($R system-actions:read 10)" == *"update"* ]]; then pass "update badge \"Update now\" starts the update"; else fail "update now" "$($R system-actions:read 10)"; fi
$R update-fake:failed 10 >/dev/null
press_in menubar "The update failed, show why" >/dev/null
wait_for_text 10 "Show log" $R controls:popover 30
$R controls:popover 30 | sed 's/ ;; /\n/g' | sed "s#^#update|#" >> "$WORK/update-controls.txt"
press_in popover "Show log" >/dev/null
press_in popover "Check again" >/dev/null
wait_for_text 10 "check for updates" $R system-actions:read 10
actions=$($R system-actions:read 10)
if [[ "$actions" == *"update.log"* && "$actions" == *"check for updates"* ]]; then pass "failed update \"Show log\" and \"Check again\""; else fail "failed update buttons" "$actions"; fi
$R update-fake:idle 10 >/dev/null
$R close-panel 10 >/dev/null
open_settings
$R "settings-page:Updates and feedback" 10 >/dev/null
wait_for_text 10 "|Check now" $R controls:settings 30
if [[ "$($R controls:settings 30)" == *"|Check now"* ]]; then
    # A fresh record, so only "Check now" can put "check for updates" in it.
    $R system-actions:start 10 >/dev/null
    press_in settings "Check now" >/dev/null
    checked=$($R system-actions:read 10)
    checks_before=$(setting_value checkForUpdates)
    press_in settings "Check GitHub for new versions" >/dev/null
    checks_flipped=$(setting_value checkForUpdates)
    press_in settings "Check GitHub for new versions" >/dev/null
    if [[ "$checked" == *"check for updates"* ]] && [ "$checks_before" != "$checks_flipped" ]; then pass "settings \"Check now\" and \"Check GitHub for new versions\""; else fail "settings update checks" "$checks_before $checks_flipped"; fi
fi
$R system-actions:stop 10 >/dev/null
$R close-windows 10 >/dev/null

section "what's new buttons"
$R whats-new 10 >/dev/null
wait_for_text 10 whats-new windows_now
$R controls:whats-new 30 | sed 's/ ;; /\n/g' | sed "s#^#whats-new|#" > "$WORK/whats-new-controls.txt"
press_in whats-new "Got it" >/dev/null
wait_for_no_text 10 whats-new windows_now
if [[ "$(windows_now)" != *"whats-new"* ]]; then pass "What's New \"Got it\" closes it"; else fail "What's New Got it" "$(windows_now)"; fi

section "step guide and comparison buttons"
$R screenshot-full 40 >/dev/null
$R screenshot-full 40 >/dev/null
$R close-windows 10 >/dev/null
$R "guide-latest:2:$WORK" 30 >/dev/null
wait_for_text 10 step-guide windows_now
$R controls:step-guide 30 | sed 's/ ;; /\n/g' | sed "s#^#step-guide|#" > "$WORK/guide-controls.txt"
$R "set-value:step-guide:Caption of step 1=first" 10 >/dev/null
$R "set-value:step-guide:Caption of step 2=second" 10 >/dev/null
press_in step-guide "Move step 2 up" >/dev/null
moved_up=$($R control-value:step-guide:"Caption of step 1" 10)
press_in step-guide "Move step 1 down" >/dev/null
moved_down=$($R control-value:step-guide:"Caption of step 1" 10)
$R "set-value:step-guide:Title=Buttons guide" 10 >/dev/null
press_in step-guide "Copy image" >/dev/null
guide_image=$($R pasteboard-types 10)
$R system-actions:start 10 >/dev/null
rm -f "$WORK/guide-test.pdf" "$WORK/guide-test.png"
$R "system-actions:files:$WORK/guide-test.pdf" 10 >/dev/null
press_in step-guide "Save PDF…" >/dev/null
$R "system-actions:files:$WORK/guide-test.png" 10 >/dev/null
press_in step-guide "Save PNG…" >/dev/null
wait_for 10 test -s "$WORK/guide-test.png"
$R system-actions:stop 10 >/dev/null
press_in step-guide "Remove step 2" >/dev/null
if [ "$moved_up" = "value=second" ] && [ "$moved_down" = "value=first" ]; then pass "step guide \"Move step up\" and \"Move step down\" reorder the captions"; else fail "step guide move" "$moved_up $moved_down"; fi
if [[ "$guide_image" == *png* || "$guide_image" == *tiff* ]] && file "$WORK/guide-test.pdf" | grep -q PDF && file "$WORK/guide-test.png" | grep -q PNG; then pass "step guide \"Copy image\", \"Save PDF…\" and \"Save PNG…\" with the typed title"; else fail "step guide copy and save" "$guide_image"; fi
if [ "$($R control-value:step-guide:"Caption of step 2" 10)" = "not found" ]; then pass "step guide \"Remove step\" takes it out"; else fail "step guide remove"; fi
$R close-windows 10 >/dev/null
$R compare-latest 30 >/dev/null
wait_for_text 10 compare windows_now
$R controls:compare 30 | sed 's/ ;; /\n/g' | sed "s#^#compare|#" > "$WORK/compare-controls.txt"
compare_ok=""
for mode in "Side by side" "Slider" "Changes"; do
    press_in compare "$mode" >/dev/null
    printf '' | pbcopy
    press_in compare "Copy image" >/dev/null
    if ! $R pasteboard-types 10 | grep -qE "png|tiff"; then compare_ok="$compare_ok $mode"; fi
done
if [ -z "$compare_ok" ]; then pass "comparison modes and \"Copy image\" in each"; else fail "comparison modes" "$compare_ok"; fi
$R close-windows 10 >/dev/null
if [ "$($R compare-latest:video 30)" = "opened" ]; then
    $R controls:compare 30 | sed 's/ ;; /\n/g' | sed "s#^#compare|#" >> "$WORK/compare-controls.txt"
    press_in compare "Play both" >/dev/null
    wait_for_text 10 "|Pause both" $R controls:compare 30
    playing=$($R controls:compare 30)
    press_in compare "Pause both" >/dev/null
    paused=$($R control-value:compare:Position 10)
    # Real time: the position of paused videos must stay the same over this time.
    sleep 0.6
    still=$($R control-value:compare:Position 10)
    press_in compare "Position#increment" >/dev/null
    position=$($R control-value:compare:Position 10)
    grew=$(python3 -c "import sys; print(float(sys.argv[2]) > float(sys.argv[1]))" "${still#value=}" "${position#value=}" 2>/dev/null)
    if [[ "$playing" == *"|Pause both"* && "$paused" == "$still" && "$grew" == True ]]; then pass "clip comparison \"Play both\", \"Pause both\" and the position slider"; else fail "clip comparison" "$paused / $still / $position"; fi
    # The two clips have no play buttons of their own that could pull them apart.
    own=$($R controls:compare 30 | sed 's/ ;; /\n/g' | grep -vE "\|(Side by side|Slider|Changes|Copy image|Play both|Pause both|Position)$")
    if [ -z "$own" ]; then pass "compared clips have no player buttons of their own"; else fail "compared clips player buttons" "$own"; fi
    $R close-windows 10 >/dev/null
else
    fail "clip comparison did not open"
fi

section "design overlay and recording bar buttons"
$R overlay-test:2 10 >/dev/null
wait_for_text 10 design-overlay windows_now
$R controls:design-overlay 30 | sed 's/ ;; /\n/g' | sed "s#^#design-overlay|#" > "$WORK/overlay-controls.txt"
alpha_before=$($R overlay-state 10)
press_in design-overlay "Opacity#increment" >/dev/null
alpha_after=$($R overlay-state 10)
press_in design-overlay "@1x" >/dev/null
one_x=$($R overlay-state 10)
press_in design-overlay "@2x" >/dev/null
press_in design-overlay "Click through to the app" >/dev/null
through=$($R overlay-state 10)
press_in design-overlay "Click through to the app" >/dev/null
if [ "$alpha_before" != "$alpha_after" ] && [ "$one_x" != "$alpha_after" ]; then pass "design overlay opacity slider and export scale"; else fail "design overlay controls" "$alpha_before / $alpha_after / $one_x"; fi
if [[ "$through" == *"clickThrough=true"* && "$($R overlay-state 10)" == *"clickThrough=false"* ]]; then pass "design overlay \"Click through to the app\" switch"; else fail "design overlay click through" "$through"; fi
press_in design-overlay "Close the overlay" >/dev/null
if [[ "$($R overlay-close 10)" == "open=false" ]]; then pass "design overlay \"Close the overlay\""; else fail "design overlay close"; fi

$R draw-toggle 10 >/dev/null
wait_for_text 10 recording-bar windows_now
$R controls:recording-bar 30 | sed 's/ ;; /\n/g' | sed "s#^#recording-bar|#" > "$WORK/bar-controls.txt"
bar=$($R controls:recording-bar 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2-)
tool_label=$(echo "$bar" | grep -E "^Rectangle" | head -1)
press_in recording-bar "$tool_label" >/dev/null
press_in recording-bar "yellow" >/dev/null
picked=$(tools_now)
fade_label=$(echo "$bar" | grep -E "^Marks " | head -1)
press_in recording-bar "$fade_label" >/dev/null
fade_flipped=$(tools_now)
press_in recording-bar "$($R controls:recording-bar 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -E "^Marks " | head -1)" >/dev/null
undo=$(press_in recording-bar "Undo the last mark (⌘Z)")
clear=$(press_in recording-bar "Clear all marks from the screen (Delete)")
draw_label=$(echo "$bar" | grep -E "^Stop drawing" | head -1)
press_in recording-bar "$draw_label" >/dev/null
not_drawing=$(tools_now)
press_in recording-bar "Close the drawing bar" >/dev/null
wait_for_no_text 10 recording-bar windows_now
if [[ "$picked" == *"liveTool=rectangle"* && "$picked" == *"liveColor=yellow"* && "$picked" == *"fade=true"* && "$fade_flipped" == *"fade=false"* && "$(tools_now)" == *"fade=true"* ]]; then pass "drawing bar tool, color and fade buttons"; else fail "drawing bar tool, color, fade" "$picked / $fade_flipped"; fi
if [ "$undo" = pressed ] && [ "$clear" = pressed ] && [[ "$not_drawing" == *"drawing=false"* && "$(windows_now)" != *"recording-bar"* ]]; then pass "drawing bar undo, clear, stop drawing and close"; else fail "drawing bar" "$undo $clear $not_drawing $(windows_now)"; fi
live_field() { echo "$1" | tr ' ' '\n' | grep "^$2=" | cut -d= -f2-; }
# Text on the screen: with Text, a click puts a field there; Return keeps the text as a mark,
# Esc drops it. Typed with real keys, so any keyboard layout works.
$R "activate-app:$BROWSER" 10 >/dev/null
wait_browser_front
# Real time: the window becomes key a moment after the app is in front.
sleep 0.5
$R draw-toggle 10 >/dev/null
wait_for_text 10 recording-bar windows_now
press_in recording-bar "Text" >/dev/null
press_in recording-bar "coral" >/dev/null
# Marks stay for this check: a mark that fades after 3.8 s must not make it flaky.
press_in recording-bar "Marks fade after 3 s (click to keep)" >/dev/null
live=$($R live-state 10)
lx=$(live_field "$live" x); ly=$(live_field "$live" y); lw=$(live_field "$live" w); lh=$(live_field "$live" h)
text_x=$((lx + lw / 3))
text_y=$((ly + lh / 3))
$R "post-click:$text_x,$text_y" 10 >/dev/null
wait_for_text 10 "typing=true" $R live-state 10
typing=$($R live-state 10)
$R post-text:Login 10 >/dev/null
$R post-key:36:none 10 >/dev/null
wait_for_text 10 "lastText=Login" $R live-state 10
typed=$($R live-state 10)
text_pixels=$(live_field "$($R "screen-color:$text_x,$text_y,160,50:FF6B4A" 20)" coral)
if [ "$(live_field "$typing" typing)" = "true" ] && [ "$(live_field "$typed" lastKind)" = "text" ] && [ "$(live_field "$typed" lastText)" = "Login" ] && [ "$(live_field "$typed" typing)" = "false" ]; then pass "drawing bar \"Text\": a click and typing put text on the screen"; else fail "drawing text on the screen" "$typing / $typed"; fi
if [ "${text_pixels:-0}" -gt 150 ] 2>/dev/null; then pass "the text shows on the screen"; else fail "the text shows on the screen" "$text_pixels"; fi
marks_before=$(live_field "$typed" marks)
$R "post-click:$((text_x + 200)),$((text_y + 150))" 10 >/dev/null
wait_for_text 10 "typing=true" $R live-state 10
$R post-text:Dropped 10 >/dev/null
$R post-key:53:none 10 >/dev/null
wait_for_text 10 "typing=false" $R live-state 10
cancelled=$($R live-state 10)
if [ "$(live_field "$cancelled" typing)" = "false" ] && [ "$(live_field "$cancelled" drawing)" = "true" ] && [ "$(live_field "$cancelled" lastText)" = "Login" ] && [ "$(live_field "$cancelled" marks)" -le "$marks_before" ]; then pass "Esc drops the text being typed and keeps drawing"; else fail "Esc while typing text" "$cancelled"; fi
press_in recording-bar "Marks stay (click to fade)" >/dev/null
$R draw-hide 10 >/dev/null
before=$(capture_count)
press_menu Record "Start recording" >/dev/null
wait_for_text 15 "Stop and throw the recording away" $R controls:recording-bar 30
bar=$($R controls:recording-bar 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2-)
$R controls:recording-bar 30 | sed 's/ ;; /\n/g' | sed "s#^#recording-bar|#" >> "$WORK/bar-controls.txt"
press_in recording-bar "$(echo "$bar" | grep -E "^Pause the recording" | head -1)" >/dev/null
paused=$(tools_now)
press_in recording-bar "$($R controls:recording-bar 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -E "^Resume the recording" | head -1)" >/dev/null
resumed=$(tools_now)
press_in recording-bar "Stop and throw the recording away without saving" >/dev/null
# Negative check: a recording wrongly saved would show up as a new capture within this time.
sleep 2
if [[ "$paused" == *"paused=true"* && "$resumed" == *"paused=false"* && "$(tools_now)" == *"recording=false"* && "$(capture_count)" = "$before" ]]; then pass "recording bar pause, resume and \"throw away\" saves nothing"; else fail "recording bar" "$paused / $resumed / $(capture_count)"; fi
press_menu Record "Start recording" >/dev/null
stop_button_shown() { $R controls:recording-bar 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -qx Stop; }
wait_for 15 stop_button_shown
press_in recording-bar Stop >/dev/null
wait_for_value 20 "$((before + 1))" capture_count
if [ "$(capture_count)" = "$((before + 1))" ]; then pass "recording bar \"Stop\" saves the recording"; else fail "recording bar Stop"; fi
$R close-windows 10 >/dev/null

section "every control has a check"
# The controls on screen now, against scripts/check/controls.txt: a new button without a check fails.
listing="$WORK/controls.txt"
: > "$listing"
$R close-panel 10 >/dev/null
$R press-status-item 10 >/dev/null
for tab in Capture Record Tools Recent Space; do
    $R "press:menubar:$tab" 10 >/dev/null
    # Real time: the panel draws the tab before its controls are read.
    sleep 0.5
    $R controls:menubar 30 | sed 's/ ;; /\n/g' | sed "s#^#menubar/$tab|#" >> "$listing"
done
$R close-panel 10 >/dev/null
press_menu Capture "Open settings: buffer, shortcuts, storage and more" >/dev/null
wait_for_text 10 settings windows_now
$R tall-window:settings 10 >/dev/null
# Settings shows one page at a time: list every page.
for page in "General" "Buffer and recording" "Bug reports" "Storage" "Shortcuts" "Updates and feedback"; do
    $R "settings-page:$page" 10 >/dev/null
    $R controls:settings 30 | sed 's/ ;; /\n/g' | sed "s#^#settings|#" >> "$listing"
done
$R close-windows 10 >/dev/null
press_menu Recent "All captures" >/dev/null
wait_for_text 10 history windows_now
$R controls:history 30 | sed 's/ ;; /\n/g' | sed "s#^#history|#" >> "$listing"
$R "menu-items:history:More actions" 10 | sed 's/ ;; /\n/g' | sed "s#^#history-menu|AXMenuItem|#" >> "$listing"
$R close-windows 10 >/dev/null
# Windows that need a state to show their controls were listed by their own sections.
for listed in onboarding feedback update whats-new guide compare overlay bar picker; do
    if [ -s "$WORK/$listed-controls.txt" ]; then grep -v '^[^|]*|$' "$WORK/$listed-controls.txt" | sort -u >> "$listing"; else fail "no controls listed for $listed: run its section first"; fi
done
# The toolbox controls were listed tool by tool in "toolbox buttons".
if [ -s "$WORK/toolbox-controls.txt" ]; then sed "s#^#toolbox|#" "$WORK/toolbox-controls.txt" | sort -u >> "$listing"; else fail "toolbox controls listing is empty: run the toolbox section first"; fi
# Disk Space on a made-up home: every section, with its questions open. Nothing that removes is
# pressed unless the made-up home is in use.
listing_home=$($R space-fake-home:on 60)
list_space() { $R controls:space 30 | sed 's/ ;; /\n/g' | sed "s#^#space|#" >> "$listing"; }
if [ -z "$listing_home" ] || [ ! -d "$listing_home/Projects" ] || [[ "$($R space-review-state:projects 10)" == refused* ]]; then
    fail "the Space controls need the made-up home" "$listing_home"
else
$R open-space:Clean\ up 10 >/dev/null
wait_for 10 space_control_shown "Review App caches"
list_space
# A cache list with its confirmation open, then the project list: found, asking, and after the move.
$R "press:space:Review App caches" 10 >/dev/null
wait_for_text 10 "Delete " $R controls:space 30
list_space
$R "press:space:$($R controls:space 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -E "^Delete [0-9]+ items?, " | head -1)" 10 >/dev/null
list_space
$R "press:space:Cancel" 10 >/dev/null
$R "open-space:Clean up:projects" 10 >/dev/null
wait_for 10 space_control_shown "Find projects"
list_space
$R "press:space:Find projects" 10 >/dev/null
# Real time: catches the project search while it still runs.
sleep 0.3
list_space
wait_for_text 15 "scanning=false" $R space-review-state:projects 10
list_space
project_footer=$($R controls:space 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -E "^Move 1 folder, " | head -1)
$R "press:space:$project_footer" 10 >/dev/null
list_space
$R "press:space:$project_footer" 10 >/dev/null
# Real time: the folder is moved and the list redraws.
sleep 1.5
list_space
# "Delete … for good" asking, then Cancel: the folder stays in the made-up Trash.
$R "press:space:$($R controls:space 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -E "^Delete this folder for good, " | head -1)" 10 >/dev/null
list_space
$R "press:space:Cancel" 10 >/dev/null
$R "press:space:Folders" 10 >/dev/null
list_space
$R space-scan 60 >/dev/null
$R "press:space:$($R controls:space 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -E "^Folder Home, " | head -1)" 10 >/dev/null
list_space
$R "press:space:Largest files" 10 >/dev/null
$R "press:space:Move test-big.bin to Trash" 10 >/dev/null
list_space
fi
$R close-windows 10 >/dev/null
$R space-fake-home:off 60 >/dev/null
$R screenshot-full 40 >/dev/null
wait_for_text 10 "Save to folder" $R controls:screenshot: 30
$R controls:screenshot: 30 | sed 's/ ;; /\n/g' | sed "s#^#screenshot:|#" >> "$listing"
$R close-windows 10 >/dev/null
$R save:5 60 >/dev/null
wait_for_text 10 "Save to folder" $R controls:video: 30
$R controls:video: 30 | sed 's/ ;; /\n/g' | sed "s#^#video:|#" >> "$listing"
$R close-windows 10 >/dev/null
# A window that did not open lists nothing, and nothing to list would pass without looking.
for area in menubar/Capture menubar/Record menubar/Tools menubar/Recent menubar/Space settings history space "screenshot:" "video:"; do
    if [ "$(grep -c "^$area|AX" "$listing")" -lt 3 ]; then fail "no controls listed for $area" "the window did not open in time"; fi
done
if coverage=$(python3 -I scripts/check/control-coverage.py "$listing"); then pass "every control of every window has a check ($(wc -l < "$listing" | tr -d ' ') controls)"; else fail "controls without a check" "$coverage"; fi

section "settings buttons"
open_settings
permissions=$($R permissions 10)
# Each switch flips its setting, and pressing again puts it back.
for row in "Keep all displays (pick one or all side by side in the editor)|captureAllDisplays" "Show the mouse pointer|showsCursor" "Start the buffer when the app opens|startBufferOnLaunch" "Offer a report after $APP_NAME crashes|offerCrashReports" "Save a clip when an app crashes|saveOnCrash" "Attach the app's system log to clips|attachSystemLogs" "Record system audio|recordSystemAudio" "Record microphone|recordMicrophone" "Record clicks|recordClicks" "Record shortcut keys|recordKeys" "Show what I type in steps|recordTypedText" "Copy a new screenshot to the clipboard|copyScreenshots" "Read the browser tab URL|readBrowserURL"; do
    label="${row%%|*}"
    key="${row##*|}"
    if [ "$key" = "recordMicrophone" ] && [[ "$permissions" != *"microphone=true"* ]]; then
        echo "SKIP  settings \"$label\": needs microphone=true, macOS would ask"
        continue
    fi
    first=$(setting_value "$key")
    press_now settings "$label" >/dev/null
    wait_for 10 setting_differs "$key" "$first"
    second=$(setting_value "$key")
    press_now settings "$label" >/dev/null
    wait_for_value 10 "$first" setting_value "$key"
    third=$(setting_value "$key")
    if [ "$first" != "$second" ] && [ "$first" = "$third" ]; then pass "settings switch \"$label\" turns $key on and off"; else fail "settings switch \"$label\"" "$first → $second → $third"; fi
done

# Buttons that hand something to macOS say what they would open instead of opening it.
$R system-actions:start 10 >/dev/null
for row in "Choose…|choose folder" "Show in Finder|/Captures" "Open at login|login "; do
    label="${row%%|*}"
    expected="${row##*|}"
    press_in settings "$label" >/dev/null
    wait_for_text 10 "$expected" $R system-actions:read 10
    recorded=$($R system-actions:read 10)
    if [[ "$recorded" == *"$expected"* ]]; then pass "settings button \"$label\" asks macOS for the right thing"; else fail "settings button \"$label\"" "$recorded"; fi
done
press_in settings "Open at login" >/dev/null
# Permissions page: each permission has Allow… (not given yet) or Open… (given), and each asks
# macOS or opens its own part of System Settings.
$R settings-page:Permissions 10 >/dev/null
wait_for_text 10 "Screen & System Audio Recording" $R controls:settings 30
permission_controls=$($R controls:settings 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2-)
# actions_since <count>: what the buttons recorded after the first <count> actions.
actions_since() { $R system-actions:read 10 | sed 's/ ;; /\n/g' | tail -n +$(($1 + 1)); }
pressed=0
wrong=""
for row in "Screen & System Audio Recording|ScreenCapture|Screen Recording" "Accessibility|Privacy_Accessibility|Accessibility" "Microphone|Privacy_Microphone|Microphone" "Camera|Privacy_Camera|Camera" "Browsers (Automation)|Privacy_Automation|Automation"; do
    title="${row%%|*}"
    rest="${row#*|}"
    pane="${rest%%|*}"
    asked="${rest##*|}"
    before_count=$($R system-actions:read 10 | sed 's/ ;; /\n/g' | grep -c .)
    if echo "$permission_controls" | grep -qx "Open $title in System Settings"; then
        press_now settings "Open $title in System Settings" >/dev/null
        expected="$pane"
    else
        press_now settings "Allow $title" >/dev/null
        expected="$asked"
    fi
    wait_for_text 10 "$expected" actions_since "$before_count"
    recorded=$(actions_since "$before_count")
    if [[ "$recorded" == *"$expected"* ]]; then pressed=$((pressed + 1)); else wrong="$wrong $title:$recorded"; fi
done
if [ "$pressed" = "5" ]; then pass "settings permissions page asks macOS or opens System Settings for each permission"; else fail "settings permissions page" "$wrong"; fi
$R buffer-needs-permission:on 10 >/dev/null
wait_for_text 10 Relaunch $R controls:settings 30
relaunch_result=$(press_in settings Relaunch)
$R buffer-needs-permission:off 10 >/dev/null
if [ "$relaunch_result" = "pressed" ] && [[ "$($R system-actions:read 10)" == *"relaunch"* ]]; then pass "settings \"Relaunch\" restarts the app after Screen Recording is allowed"; else fail "settings Relaunch" "$relaunch_result"; fi
$R settings-page:General 10 >/dev/null
$R system-actions:stop 10 >/dev/null

started_before=$(grep -c "buffer\[.*\] started" "$LOG")
cursor_before=$(setting_value showsCursor)
press_now settings "Show the mouse pointer" >/dev/null
# The setting is saved before the buffer restarts with it.
wait_for 10 setting_differs showsCursor "$cursor_before"
press_in settings "Restart buffer" >/dev/null
wait_for 20 buffer_started_above "$started_before"
started_mid=$(grep -c "buffer\[.*\] started" "$LOG")
press_in settings "Show the mouse pointer" >/dev/null
press_in settings "Restart buffer" >/dev/null
wait_for 20 buffer_started_above "$started_mid"
if [ "$(grep -c "buffer\[.*\] started" "$LOG")" -gt "$started_before" ]; then pass "settings \"Restart buffer\" restarts the buffer with the new settings"; else fail "settings \"Restart buffer\""; fi

for row in "Report a problem…|feedback" "Suggest a feature…|feedback" "Show the welcome guide|onboarding" "Show what's new|whats-new"; do
    label="${row%%|*}"
    window="${row##*|}"
    open_settings
    press_in settings "$label" >/dev/null
    wait_for_text 10 "$window" windows_now
    if [[ "$(windows_now)" == *"$window"* ]]; then pass "settings \"$label\" opens the $window window"; else fail "settings \"$label\"" "$(windows_now)"; fi
done

open_settings
fields_before=$($R fields-count 10)
press_in settings "New field" >/dev/null
wait_for 10 fields_count_not "$fields_before"
fields_added=$($R fields-count 10)
press_in settings "Remove field#last" >/dev/null
wait_for_value 10 "$fields_before" $R fields-count 10
fields_after=$($R fields-count 10)
if [ "$fields_added" != "$fields_before" ] && [ "$fields_after" = "$fields_before" ]; then pass "settings \"New field\" adds a report field and \"Remove field\" removes it"; else fail "settings add and remove field" "$fields_before / $fields_added / $fields_after"; fi

# A suggested name adds a field with that name.
open_settings
$R "settings-page:Bug reports" 10 >/dev/null
wait_for_text 10 "|Include Device" $R controls:settings 30
fields_before=$($R fields-count 10)
suggestion=$($R controls:settings 30 | sed 's/ ;; /\n/g' | grep -E "^AXButton\|(Stand|Build|Test account|Browser profile|Feature flag|Severity)$" | head -1 | cut -d'|' -f2)
press_in settings "$suggestion" >/dev/null
wait_for 10 fields_count_not "$fields_before"
fields_added=$($R fields-count 10)
newest_field=$($R fields-read 10 | tr ',' '\n' | tail -1)
press_in settings "Remove field#last" >/dev/null
wait_for_value 10 "$fields_before" $R fields-count 10
if [ -n "$suggestion" ] && [ "$newest_field" = "$suggestion=" ] && [ "$fields_added" != "$fields_before" ] && [ "$($R fields-count 10)" = "$fields_before" ]; then pass "settings suggestion \"$suggestion\" adds a field with that name"; else fail "settings field suggestion" "$suggestion $fields_before / $fields_added, newest $newest_field"; fi

# A changed shortcut and "Reset to defaults"; a shortcut button waits for keys, Esc cancels.
# Reset would also drop shortcuts the person set, so with their own shortcuts it is skipped.
if [ -n "$(defaults read "$BUNDLE_ID" customHotKeys 2>/dev/null | tr -d '{}() \n')" ]; then
    echo "SKIP  settings \"Reset to defaults\": the person has their own shortcuts"
else
    press_in settings "Save the last 30 s: ⌥⇧1" >/dev/null
    # Real time: the shortcut button waits for keys; Esc follows.
    sleep 0.5
    $R post-key:53:none 10 >/dev/null
    $R hotkey-set:ruler:25:cmd,shift 10 >/dev/null
    has_custom_ruler_hotkey() { defaults read "$BUNDLE_ID" customHotKeys 2>/dev/null | grep -q ruler; }
    no_custom_ruler_hotkey() { ! has_custom_ruler_hotkey; }
    # The shortcut is saved before Reset, so a Reset that does nothing fails.
    wait_for 5 has_custom_ruler_hotkey
    open_settings
    press_now settings "Reset to defaults" >/dev/null
    # Reset writes the preferences; they are read from outside the app.
    wait_for 10 no_custom_ruler_hotkey
    if [ "$($R control-value:settings:"Save the last 30 s: ⌥⇧1" 10)" != "not found" ] && ! defaults read "$BUNDLE_ID" customHotKeys 2>/dev/null | grep -q ruler; then pass "settings \"Reset to defaults\" restores the shortcuts, a shortcut button keeps its keys after Esc"; else fail "settings shortcuts reset"; fi
fi

# Clean up now with limits that keep everything: it runs and deletes nothing. The limits are
# changed inside the app (defaults written from outside would not reach it) and put back.
saved_days=$(setting_value keepCapturesDays)
saved_gb=$(setting_value maxCapturesGB)
saved_crash_days=$(setting_value keepCrashClipsDays)
$R setting-write:keepCapturesDays=36500 10 >/dev/null
$R setting-write:maxCapturesGB=0 10 >/dev/null
$R setting-write:keepCrashClipsDays=36500 10 >/dev/null
open_settings
press_in settings "Clean up now" >/dev/null
wait_for 15 recent_log_has "clean up now: deleted 0"
if tail -20 "$LOG" | grep -q "clean up now: deleted 0"; then pass "settings \"Clean up now\" applies the rules (nothing that old to delete)"; else fail "settings \"Clean up now\""; fi
$R "setting-write:keepCapturesDays=$saved_days" 10 >/dev/null
$R "setting-write:maxCapturesGB=$saved_gb" 10 >/dev/null
$R "setting-write:keepCrashClipsDays=$saved_crash_days" 10 >/dev/null

# Pickers: choosing another item changes the setting, choosing the first one puts it back. The
# timed clean-up waits meanwhile, so a storage limit on for a moment deletes nothing.
$R cleanup-pause:on 10 >/dev/null
for row in "Keep the last|bufferMinutes" "Buffer frame rate|framesPerSecond" "Recording frame rate|recordingFramesPerSecond" "Resolution|maxHeight" "Copy bug report as|bugReportFormat" "Delete captures older than|keepCapturesDays" "Delete crash clips older than|keepCrashClipsDays" "Keep captures under|maxCapturesGB"; do
    label="${row%%|*}"
    key="${row##*|}"
    shown=$($R control-value:settings:"$label" 10)
    shown="${shown#value=}"
    before=$(setting_value "$key")
    other=$($R "menu-items:settings:$label" 10 | sed 's/ ;; /\n/g' | grep -vxF "$shown" | head -1)
    $R "choose-now:settings:$label => $other" 10 >/dev/null
    wait_for 5 setting_differs "$key" "$before"
    changed=$(setting_value "$key")
    $R "choose-now:settings:$label => $shown" 10 >/dev/null
    wait_for_value 5 "$before" setting_value "$key"
    after=$(setting_value "$key")
    # Never leave a storage limit (or any choice) changed when choosing back did not work.
    if [ "$after" != "$before" ]; then $R "setting-write:$key=$before" 10 >/dev/null; fi
    if [ -n "$other" ] && [ "$changed" != "$before" ] && [ "$after" = "$before" ]; then pass "settings picker \"$label\" sets $key ($shown → $other → back)"; else fail "settings picker \"$label\"" "$shown/$other: $before → $changed → $after"; fi
done
$R cleanup-pause:off 10 >/dev/null
$R close-windows 10 >/dev/null

section "settings pages and report fields"
open_settings
# Each sidebar button shows its own page: a control of that page appears, one of another goes.
for row in "General|Open at login" "Buffer and recording|Keep the last" "Bug reports|Copy bug report as" "Storage|Clean up now" "Shortcuts|Reset to defaults" "Updates and feedback|Report a problem…"; do
    page="${row%%|*}"
    own="${row##*|}"
    press_in settings "Page: $page" >/dev/null
    shown=$($R controls:settings 30)
    if [ "$page" = "General" ]; then other="Clean up now"; else other="Open at login"; fi
    if [[ "$shown" == *"|$own"* && "$shown" != *"|$other"* ]]; then pass "settings sidebar \"$page\" shows that page"; else fail "settings sidebar \"$page\"" "$shown"; fi
done
# Fields the app fills in: every one is listed, can be turned off and renamed, and a new
# capture's report follows. The person's own choices are put back after.
# Kept in a file as JSON: values may hold ":", "," or nothing.
saved_hidden=$(setting_value hiddenEnvironmentFields)
saved_renamed=$(setting_value renamedEnvironmentFields)
saved_fields=$($R fields-read 10)
$R "report-settings-save:$WORK/report-settings-2.json" 10 >/dev/null
press_in settings "Page: Bug reports" >/dev/null
shown=$($R controls:settings 30)
listed=0
for field in macOS Device Display App URL Locale Appearance Time; do
    if [[ "$shown" == *"|Include $field"* && "$shown" == *"|Name for $field"* ]]; then listed=$((listed + 1)); fi
done
if [ "$listed" = "8" ]; then pass "settings lists the 8 fields filled in by $APP_NAME with a switch and a name"; else fail "settings standard fields" "$listed of 8"; fi
$R "setting-write:hiddenEnvironmentFields=" 10 >/dev/null
$R "setting-write:renamedEnvironmentFields=" 10 >/dev/null
switched=0
for field in macOS Device Display App URL Locale Appearance Time; do
    press_in settings "Include $field" >/dev/null
    hidden_now=$(setting_value hiddenEnvironmentFields)
    press_in settings "Include $field" >/dev/null
    if [ "$hidden_now" = "$field" ] && [ -z "$(setting_value hiddenEnvironmentFields)" ]; then switched=$((switched + 1)); else echo "    Include $field: $hidden_now / $(setting_value hiddenEnvironmentFields)"; fi
done
if [ "$switched" = "8" ]; then pass "settings switch \"Include Locale\" turns the field off and on, and so do the other 7"; else fail "settings Include switches" "$switched of 8"; fi
$R "set-value:settings:Name for Device=Model" 10 >/dev/null
renamed_now=$(setting_value renamedEnvironmentFields)
if [ "$renamed_now" = "Device=Model" ]; then pass "settings \"Name for Device\" renames the field"; else fail "settings Name for Device" "$renamed_now"; fi
# Cleared while still typing, the field stays empty (the usual name is only its placeholder).
$R "set-value-typing:settings:Name for Device=" 10 >/dev/null
typed_empty=$($R "control-value:settings:Name for Device" 10)
$R "set-value:settings:Name for Device=Model" 10 >/dev/null
if [ "$typed_empty" = "value=" ]; then pass "settings \"Name for Device\" stays empty while you clear it"; else fail "settings clearing Name for Device" "$typed_empty"; fi
press_in settings "Include Locale" >/dev/null
$R fields:Stand=stage-3 10 >/dev/null
$R close-windows 10 >/dev/null
$R screenshot-full 40 >/dev/null
$R close-windows 10 >/dev/null
$R report:markdown 10 >/dev/null
report=$(pbpaste)
if [[ "$report" == *"- Model: "* && "$report" != *"- Device: "* && "$report" != *"- Locale: "* && "$report" == *"- Stand: stage-3"* ]]; then pass "a new capture's report has the renamed field, not the one turned off, and your field"; else fail "report follows the field settings" "$report"; fi
# "Edit" next to Environment in an open editor goes to these settings, and the editor follows a
# change there at once: the field turned off leaves its report.
# Settings left on another page, so only the button can bring it to Bug reports.
$R close-windows 10 >/dev/null
$R settings-page:General 10 >/dev/null
$R screenshot-full 40 >/dev/null
wait_for_text 10 "Save to folder" $R controls:screenshot: 30
edit_result=$(press_in screenshot: Edit)
wait_for_text 10 "|Include Device" $R controls:settings 30
shown=$($R controls:settings 30)
if [ "$edit_result" = "pressed" ] && [[ "$shown" == *"|Include Device"* ]]; then pass "editor \"Edit\" next to Environment opens Settings on Bug reports"; else fail "editor Edit environment" "$edit_result"; fi
$R "setting-write:hiddenEnvironmentFields=Appearance" 10 >/dev/null
# Real time: the report reads the setting a moment after it is written.
sleep 1
$R report:markdown 10 >/dev/null
report=$(pbpaste)
if [[ "$report" != *"- Appearance: "* && "$report" == *"- Locale: "* ]]; then pass "an open editor's capture follows a field turned off in Settings"; else fail "open editor follows field settings" "$report"; fi
$R close-windows 10 >/dev/null
# Clearing the name brings the usual one back.
open_settings
$R "set-value:settings:Name for Device=" 10 >/dev/null
if [ -z "$(setting_value renamedEnvironmentFields)" ]; then pass "settings an empty \"Name for Device\" goes back to Device"; else fail "settings clear Name for Device" "$(setting_value renamedEnvironmentFields)"; fi
$R "report-settings-restore:$WORK/report-settings-2.json" 10 >/dev/null
if [ "$(setting_value hiddenEnvironmentFields)" = "$saved_hidden" ] && [ "$(setting_value renamedEnvironmentFields)" = "$saved_renamed" ] && [ "$($R fields-read 10)" = "$saved_fields" ]; then pass "the person's field settings are put back"; else fail "field settings restore"; fi
$R close-windows 10 >/dev/null

section "screenshot editor buttons"
# Saves go to a test folder, not the person's Desktop/$APP_NAME.
saved_output=$(setting_value outputFolderPath)
out_dir="$WORK/editor-out"
rm -rf "$out_dir"
mkdir -p "$out_dir"
$R "setting-write:outputFolderPath=$out_dir" 10 >/dev/null
$R close-windows 10 >/dev/null
$R screenshot-full 40 >/dev/null
wait_for_text 10 "Save to folder" $R controls:screenshot: 30
editor_state() { $R editor-state 10; }
editor_controls() { $R controls:screenshot: 30 | sed 's/ ;; /\n/g'; }
state_field() { echo "$1" | tr ' ' '\n' | grep "^$2=" | cut -d= -f2-; }

# Every tool button picks its tool.
for row in "select|Select" "arrow|Arrow" "callout|Arrow with text" "rectangle|Rectangle" "ellipse|Ellipse" "line|Line" "highlighter|Highlighter" "pen|Pen" "text|Text" "step|Numbered step" "blur|Blur" "magnifier|Magnifier" "crop|Crop"; do
    tool="${row%%|*}"
    title="${row##*|}"
    label=$(editor_controls | grep "^AXButton|$title (" | head -1 | cut -d'|' -f2)
    press_in screenshot: "$label" >/dev/null
    if [ "$(state_field "$(editor_state)" tool)" = "$tool" ]; then pass "editor tool button \"$title\" picks the tool"; else fail "editor tool button \"$title\"" "$label $(editor_state)"; fi
done
press_in screenshot: "$(editor_controls | grep "^AXButton|Rectangle (" | head -1 | cut -d'|' -f2)" >/dev/null

# Colors, size and fill.
for color in yellow blue green; do
    press_in screenshot: "$color" >/dev/null
    if [ "$(state_field "$(editor_state)" color)" = "$color" ]; then pass "editor color \"$color\" is picked"; else fail "editor color \"$color\"" "$(editor_state)"; fi
done
size_before=$(state_field "$(editor_state)" size)
press_in screenshot: "Bigger line width" >/dev/null
size_bigger=$(state_field "$(editor_state)" size)
press_in screenshot: "Smaller line width" >/dev/null
size_back=$(state_field "$(editor_state)" size)
if [ "$size_bigger" -gt "$size_before" ] && [ "$size_back" = "$size_before" ]; then pass "editor \"Bigger\" and \"Smaller\" change the line width ($size_before → $size_bigger)"; else fail "editor size buttons" "$size_before $size_bigger $size_back"; fi
press_in screenshot: "Fill" >/dev/null
filled=$(state_field "$(editor_state)" filled)
press_in screenshot: "No fill" >/dev/null
if [ "$filled" = true ] && [ "$(state_field "$(editor_state)" filled)" = false ]; then pass "editor \"Fill\" and \"No fill\" switch the fill"; else fail "editor fill" "$filled $(editor_state)"; fi
$R system-actions:start 10 >/dev/null
press_in screenshot: "Pick any color" >/dev/null
wait_for_text 10 NSColorPanel windows_now
if [[ "$(windows_now)" == *"NSColorPanel"* ]]; then pass "editor \"Pick any color\" opens the color panel"; else fail "editor \"Pick any color\"" "$(windows_now)"; fi
$R close-color-panel 10 >/dev/null

# Insert a picture from a file, undo and redo it, combine with another screenshot.
shot=$(ls -t "$HOME/Library/Application Support/$APP_NAME/Captures"/*/original.png | head -1)
$R "system-actions:files:$shot" 10 >/dev/null
marks_before=$(state_field "$(editor_state)" marks)
press_in screenshot: "Insert an image on top of this one: pick a file, paste one with ⌘V (Command + V) or drop it here" >/dev/null
marks_inserted=$(state_field "$(editor_state)" marks)
press_in screenshot: "Undo the last change (⌘Z)" >/dev/null
marks_undone=$(state_field "$(editor_state)" marks)
press_in screenshot: "Redo what was undone (⇧⌘Z)" >/dev/null
marks_redone=$(state_field "$(editor_state)" marks)
if [ "$marks_inserted" -eq $((marks_before + 1)) ] && [ "$marks_undone" -eq "$marks_before" ] && [ "$marks_redone" -eq "$marks_inserted" ]; then pass "editor \"Insert an image\" places a picture, \"Undo\" and \"Redo\" take it away and back"; else fail "editor insert, undo, redo" "$marks_before $marks_inserted $marks_undone $marks_redone"; fi
delete_label=$(editor_controls | grep "^AXButton|Delete " | tail -1 | cut -d'|' -f2)
press_in screenshot: "$delete_label#last" >/dev/null
if [ -n "$delete_label" ] && [ "$(state_field "$(editor_state)" marks)" -eq "$marks_before" ]; then pass "editor layer \"$delete_label\" removes that mark"; else fail "editor layer delete" "$delete_label $(editor_state)"; fi
width_before=$(state_field "$(editor_state)" width)
press_in screenshot: "Combine with another screenshot: places other images to the right" >/dev/null
editor_wider() { [ "$(state_field "$(editor_state)" width)" -gt "$1" ]; }
wait_for 10 editor_wider "$width_before"
if [ "$(state_field "$(editor_state)" width)" -gt "$width_before" ]; then pass "editor \"Combine\" places another screenshot to the right"; else fail "editor combine" "$width_before $(editor_state)"; fi

# Zoom, environment, badge.
press_in screenshot: "Fit" >/dev/null
zoom_fit=$(state_field "$(editor_state)" zoom)
press_in screenshot: "Zoom in" >/dev/null
zoom_in=$(state_field "$(editor_state)" zoom)
press_in screenshot: "Zoom out" >/dev/null
zoom_out=$(state_field "$(editor_state)" zoom)
press_in screenshot: "100%" >/dev/null
zoom_full=$(state_field "$(editor_state)" zoom)
if [ "$zoom_in" != "$zoom_fit" ] && [ "$zoom_out" = "$zoom_fit" ] && [ "$zoom_full" != "" ]; then pass "editor \"Zoom in\", \"Zoom out\", \"Fit\" and \"100%\" change the zoom"; else fail "editor zoom" "$zoom_fit $zoom_in $zoom_out $zoom_full"; fi
printf '' | pbcopy
press_in screenshot: "Copy" >/dev/null
if pbpaste | grep -q "Environment"; then pass "editor environment \"Copy\" puts the environment on the clipboard"; else fail "editor environment copy" "$(pbpaste | head -2)"; fi
press_in screenshot: "Overlay on image" >/dev/null
badge=$(state_field "$(editor_state)" badge)
press_in screenshot: "Overlay on image" >/dev/null
if [ "$badge" = true ] && [ "$(state_field "$(editor_state)" badge)" = false ]; then pass "editor \"Overlay on image\" shows and hides the environment badge"; else fail "editor badge" "$badge"; fi
# "Copy bug report": the arrow copies in the other format and remembers it, a click copies in the remembered one.
report_start=$(setting_value bugReportFormat)
printf '' | pbcopy
$R "choose:screenshot:Copy bug report as => Copy as Markdown" 10 >/dev/null
as_markdown=$(pbpaste | grep -c "^## Steps to reproduce")
printf '' | pbcopy
$R "choose:screenshot:Copy bug report as => Copy as Jira wiki" 10 >/dev/null
as_jira=$(pbpaste | grep -c "^h2. Steps to reproduce")
printf '' | pbcopy
press_in screenshot: "Copy bug report · Jira wiki" >/dev/null
again_jira=$(pbpaste | grep -c "^h2. Steps to reproduce")
remembered=$(setting_value bugReportFormat)
$R "setting-write:bugReportFormat=$report_start" 10 >/dev/null
printf '' | pbcopy
if [ "$(setting_value bugReportFormat)" = "$report_start" ] && [ "$as_markdown" = 1 ] && [ "$as_jira" = 1 ] && [ "$again_jira" = 1 ] && [ "$remembered" = "Jira wiki" ]; then pass "editor \"Copy bug report\" copies the report, its arrow picks Markdown or Jira wiki"; else fail "editor copy bug report" "$report_start: md=$as_markdown jira=$as_jira click=$again_jira remembered=$remembered"; fi

# Crop and reset, save and copy the picture.
press_in screenshot: "$(editor_controls | grep "^AXButton|Crop (" | head -1 | cut -d'|' -f2)" >/dev/null
$R editor-crop:0.1,0.1,0.5,0.5 10 >/dev/null
cropped=$(state_field "$(editor_state)" crop)
press_in screenshot: "Reset crop" >/dev/null
if [ "$cropped" = true ] && [ "$(state_field "$(editor_state)" crop)" = false ]; then pass "editor \"Reset crop\" brings the whole picture back"; else fail "editor reset crop" "$cropped $(editor_state)"; fi
# File type: picking another format changes what the editor saves, then it goes back.
format_before=$(state_field "$(editor_state)" format)
format_shown=$($R control-value:screenshot:"File type" 10)
format_shown="${format_shown#value=}"
format_item=$($R "menu-items:screenshot:File type" 10 | sed 's/ ;; /\n/g' | grep -vxF "$format_shown" | head -1)
$R "choose:screenshot:File type => $format_item" 10 >/dev/null
format_other=$(state_field "$(editor_state)" format)
$R "choose:screenshot:File type => $format_shown" 10 >/dev/null
format_back=$(state_field "$(editor_state)" format)
if [ -n "$format_item" ] && [ "$format_other" != "$format_before" ] && [ "$format_back" = "$format_before" ]; then pass "editor \"File type\" shows the format to save in and picks another ($format_before → $format_other)"; else fail "editor file type" "$format_shown/$format_item: $format_before → $format_other → $format_back"; fi
press_in screenshot: "Save to folder" >/dev/null
wait_for 10 dir_has_file "$out_dir"
saved=$(ls "$out_dir" | head -1)
if [ -n "$saved" ] && $R system-actions:read 10 | grep -q "reveal $out_dir/"; then pass "editor \"Save to folder\" writes the picture to the chosen folder and shows it ($saved)"; else fail "editor save to folder" "$saved"; fi
printf '' | pbcopy
press_in screenshot: "Copy  ⌘C" >/dev/null
wait_for_text 10 png $R pasteboard-types 10
if [ "$($R pasteboard-types 10)" != "" ] && $R pasteboard-types 10 | grep -q "png"; then pass "editor \"Copy ⌘C\" puts the picture on the clipboard"; else fail "editor copy picture" "$($R pasteboard-types 10)"; fi
printf '' | pbcopy
$R system-actions:stop 10 >/dev/null
# The next screenshot opens the way this one was left: tool, color, size, fill, badge, format.
# Every one is moved off its default first, so a choice that is not remembered shows up. (The
# tests' choices go to a store of their own, not the person's.)
press_in screenshot: "$(editor_controls | grep "^AXButton|Rectangle (" | head -1 | cut -d'|' -f2)" >/dev/null
press_in screenshot: purple >/dev/null
press_in screenshot: "Bigger line width" >/dev/null
press_in screenshot: "Bigger line width" >/dev/null
if [ "$(state_field "$(editor_state)" filled)" != true ]; then press_in screenshot: "Fill" >/dev/null; fi
if [ "$(state_field "$(editor_state)" badge)" != true ]; then press_in screenshot: "Overlay on image" >/dev/null; fi
$R "choose:screenshot:Corner => $($R "menu-items:screenshot:Corner" 10 | sed 's/ ;; /\n/g' | grep -vxF "$($R control-value:screenshot:Corner 10 | sed 's/^value=//')" | head -1)" 10 >/dev/null
$R "choose:screenshot:File type => $($R "menu-items:screenshot:File type" 10 | sed 's/ ;; /\n/g' | grep -vxF "$($R control-value:screenshot:"File type" 10 | sed 's/^value=//')" | head -1)" 10 >/dev/null
left=$(editor_state)
$R close-windows 10 >/dev/null
$R screenshot-full 40 >/dev/null
wait_for_text 10 "screenshot:" windows_now
opened=$(editor_state)
not_kept=""
for field in tool color size filled badge corner format; do
    if [ "$(state_field "$left" "$field")" != "$(state_field "$opened" "$field")" ]; then not_kept="$not_kept $field"; fi
done
if [ "$(state_field "$left" badge)" = true ] && [ "$(state_field "$left" corner)" != topRight ] && [ "$(state_field "$left" filled)" = true ] && [ -z "$not_kept" ]; then pass "a new screenshot opens with the last tool, color, size, fill, badge and format"; else fail "screenshot editor memory" "$not_kept: $left / $opened"; fi
$R close-windows 10 >/dev/null
# Later checks expect a new editor's usual start.
defaults delete "$BUNDLE_ID.tests" 2>/dev/null
$R "setting-write:outputFolderPath=$saved_output" 10 >/dev/null

section "video editor buttons"
saved_output=$(setting_value outputFolderPath)
out_dir="$WORK/video-out"
rm -rf "$out_dir"
mkdir -p "$out_dir"
$R "setting-write:outputFolderPath=$out_dir" 10 >/dev/null
video_state() { $R video-state 10; }
vfield() { echo "$1" | tr ' ' '\n' | grep "^$2=" | cut -d= -f2-; }
# A 10 s clip: right after the app starts the buffer holds less, so wait and save again.
video_has_duration() { [ -n "$(vfield "$(video_state)" duration)" ]; }
for _ in 1 2 3; do
    $R close-windows 10 >/dev/null
    $R save:10 60 >/dev/null
    wait_for 10 video_has_duration
    clip_length=$(vfield "$(video_state)" duration)
    if awk "BEGIN { exit !(${clip_length:-0} >= 9.5) }"; then break; fi
    # Real time: the buffer needs 10 s of video before the next save is long enough.
    sleep 8
done
$R system-actions:start 10 >/dev/null

press_in video: "Play" >/dev/null
wait_for_text 10 "playing=true" video_state
playing=$(vfield "$(video_state)" playing)
press_in video: "Pause" >/dev/null
if [ "$playing" = true ] && [ "$(vfield "$(video_state)" playing)" = false ]; then pass "video \"Play\" and \"Pause\" play and stop the clip"; else fail "video play and pause" "$playing"; fi
$R video-range:2,2 10 >/dev/null
press_in video: "Forward 5 seconds" >/dev/null
forward=$(vfield "$(video_state)" playhead)
press_in video: "Back 5 seconds" >/dev/null
back=$(vfield "$(video_state)" playhead)
if [ "$forward" = "7.0" ] && [ "$back" = "2.0" ]; then pass "video \"Forward 5 seconds\" and \"Back 5 seconds\" move the playhead"; else fail "video forward and back" "$forward $back"; fi
# A mark added at the last frame used to last a few microseconds and never show.
$R video-seek:end 10 >/dev/null
$R video-add-overlay:arrow 10 >/dev/null
end_state=$(video_state)
if [ "$(vfield "$end_state" lastLength)" = "3.0" ]; then pass "video a mark added at the last frame lasts 3 s"; else fail "video mark at the end" "$end_state"; fi
press_in video: "Undo the last change (⌘Z)" >/dev/null
$R video-seek:0 10 >/dev/null

# Drawing and moving marks with the real mouse, the way a person does it. Marks used to come out
# a few microseconds long at the end of a clip and slide off the frame when dragged.
stage_line=$($R video-stage 10)
sx=$(vfield "$stage_line" x)
sy=$(vfield "$stage_line" y)
sw=$(vfield "$stage_line" w)
sh=$(vfield "$stage_line" h)
at() { awk "BEGIN { printf \"%d,%d\", $sx + $sw * $1, $sy + $sh * $2 }"; }
inside() { echo "$1" | awk -F, '{ exit !($1 >= 0 && $2 >= 0 && $3 <= 1 && $4 <= 1) }'; }
# A real click on a tool button, not one through accessibility.
click_control() {
    local frame
    frame=$($R "control-frame:video:$1" 10 | sed -n 's/^frame=\([0-9-]*\),\([0-9-]*\) \([0-9]*\)x\([0-9]*\).*/\1 \2 \3 \4/p')
    if [ -z "$frame" ]; then echo "no frame"; return; fi
    local left top width height
    read -r left top width height <<< "$frame"
    $R "post-click:$(( left + width / 2 )),$(( top + height / 2 ))" 10 >/dev/null
    echo "clicked"
}
# video_field_is <field> <value>: the editor state shows that value (the caller waits for a click this way).
video_field_is() { [ "$(vfield "$(video_state)" "$1")" = "$2" ]; }
before_count=$(vfield "$(video_state)" overlays)
$R video-seek:2 10 >/dev/null
for row in "Text|text" "Arrow|arrow" "Box|rectangle" "Blur|blur"; do
    tool_label="${row%%|*}"
    tool_name="${row##*|}"
    click_control "$tool_label" >/dev/null
    wait_for 5 video_field_is tool "$tool_name"
    picked=$(vfield "$(video_state)" tool)
    click_control "$tool_label" >/dev/null
    wait_for 5 video_field_is tool select
    put_down=$(vfield "$(video_state)" tool)
    if [ "$picked" = "$tool_name" ] && [ "$put_down" = "select" ]; then pass "video a real click on \"$tool_label\" picks the tool and puts it down"; else fail "video real click on $tool_label" "$picked $put_down"; fi
done
click_control "Arrow" >/dev/null
wait_for 5 video_field_is tool arrow
$R "post-drag:$(at 0.3 0.3):$(at 0.5 0.5)" 10 >/dev/null
# Real time: the mark is drawn and the video redraws the frame.
sleep 1.5
drawn=$(video_state)
shown=$($R video-frame-diff 20)
if [ "$(vfield "$shown" changed)" -gt 50 ] 2>/dev/null; then pass "video the arrow drawn shows on the preview frame"; else fail "video arrow not on the preview" "$shown"; fi
if [ "$(vfield "$drawn" overlays)" = "$((before_count + 1))" ] && [ "$(vfield "$drawn" lastLength)" = "3.0" ] && inside "$(vfield "$drawn" lastBox)" && [ "$(vfield "$drawn" tool)" = "select" ]; then pass "video an arrow drawn with the mouse shows for 3 s inside the frame"; else fail "video draw with the mouse" "$stage_line / $drawn"; fi
# With Select, a drag away from the selected mark leaves it where it is.
box_before=$(vfield "$drawn" lastBox)
$R "post-drag:$(at 0.85 0.85):$(at 0.95 0.9)" 10 >/dev/null
# Real time: the drag is handled; the state is read right after (also for "did not move" checks).
sleep 0.8
box_after=$(vfield "$(video_state)" lastBox)
if [ "$box_after" = "$box_before" ]; then pass "video a drag away from the selected mark does not move it"; else fail "video drag away moved the mark" "$box_before → $box_after"; fi
# Dragged on the mark far past the edge, it moves and stops at the edge of the frame.
$R "post-drag:$(at 0.4 0.4):$(at 1.4 0.45)" 10 >/dev/null
# Real time: the drag is handled; the state is read right after (also for "did not move" checks).
sleep 0.8
moved=$(vfield "$(video_state)" lastBox)
if [ "$moved" != "$box_before" ] && inside "$moved"; then pass "video a mark dragged past the edge stays inside the frame"; else fail "video drag past the edge" "$box_before → $moved"; fi
# Drawn at the last frame with the mouse, it still shows for 3 s.
$R video-seek:end 10 >/dev/null
press_in video: "Box" >/dev/null
$R "post-drag:$(at 0.2 0.6):$(at 0.4 0.8)" 10 >/dev/null
# Real time: the box is drawn at the last frame.
sleep 1
last_drawn=$(video_state)
if [ "$(vfield "$last_drawn" overlays)" = "$((before_count + 2))" ] && [ "$(vfield "$last_drawn" lastLength)" = "3.0" ]; then pass "video a box drawn at the last frame shows for 3 s"; else fail "video draw at the end" "$last_drawn"; fi
press_in video: "Undo the last change (⌘Z)" >/dev/null
press_in video: "Undo the last change (⌘Z)" >/dev/null
press_in video: "Undo the last change (⌘Z)" >/dev/null
# Crop: the whole frame shows while picking, a drag draws the part to keep, a handle resizes it,
# and Done shows (and saves) only that part.
between() { awk "BEGIN { exit !($1 >= $2 && $1 <= $3) }"; }
click_control "Crop" >/dev/null
wait_for_text 10 "tool=crop" video_state
picking=$(video_state)
if [ "$(vfield "$picking" tool)" = "crop" ] && [ "$(vfield "$picking" render)" = "$(vfield "$picking" source)" ]; then pass "video \"Crop\" shows the whole frame to pick from"; else fail "video crop tool" "$picking"; fi
$R "post-drag:$(at 0.25 0.25):$(at 0.75 0.75)" 10 >/dev/null
# Real time: the drag is handled; the state is read right after (also for "did not move" checks).
sleep 0.8
drawn_crop=$(vfield "$(video_state)" crop)
$R "post-drag:$(at 0.75 0.75):$(at 0.9 0.75)" 10 >/dev/null
# Real time: the drag is handled; the state is read right after (also for "did not move" checks).
sleep 0.8
resized_crop=$(vfield "$(video_state)" crop)
IFS=, read -r crop_left crop_top crop_right crop_bottom <<< "$resized_crop"
if [ "$drawn_crop" != "none" ] && between "$crop_left" 0.23 0.27 && between "$crop_top" 0.23 0.27 && between "$crop_right" 0.87 0.93 && between "$crop_bottom" 0.73 0.77; then pass "video a drag draws the crop and its corner handle resizes it"; else fail "video draw and resize the crop" "$drawn_crop → $resized_crop"; fi
# Saving while Crop is still on writes the cropped video, not the whole frame shown.
crop_out="$WORK/crop-out"
rm -rf "$crop_out"
mkdir -p "$crop_out"
$R "setting-write:outputFolderPath=$crop_out" 10 >/dev/null
press_in video: "Save to folder" >/dev/null
# The file appears while the export still writes it; the editor shows it in Finder once it is written.
wait_for 60 dir_has_file "$crop_out"
wait_for_text 30 "reveal $crop_out/" $R system-actions:read 10
crop_file="$crop_out/$(ls "$crop_out" | head -1)"
crop_dimensions=$(avmediainfo "$crop_file" 2>/dev/null | grep -m1 "Dimensions:" | sed -E 's/.*Dimensions: ([0-9]+) x ([0-9]+).*/\1 \2/')
$R "setting-write:outputFolderPath=$out_dir" 10 >/dev/null
read -r crop_file_width crop_file_height <<< "$crop_dimensions"
if [ -n "$crop_file_width" ] && awk "BEGIN { exit !($crop_file_width / $crop_file_height > 1.15 * $(vfield "$picking" source | tr x /)) }"; then pass "video saving while cropping writes only the cropped part (${crop_file_width}x${crop_file_height})"; else fail "video save while cropping" "$crop_dimensions"; fi
click_control "Done" >/dev/null
# The preview re-renders for the cropped part: smaller than the whole frame.
crop_rendered() { local state; state=$(video_state); [ "$(vfield "$state" tool)" = select ] && [ "$(vfield "$state" render)" != "$(vfield "$state" source)" ]; }
wait_for 10 crop_rendered
cropped_state=$(video_state)
render=$(vfield "$cropped_state" render)
source_size=$(vfield "$cropped_state" source)
render_width=${render%x*}
source_width=${source_size%x*}
if [ "$(vfield "$cropped_state" tool)" = "select" ] && between "$render_width" "$(( source_width * 62 / 100 ))" "$(( source_width * 68 / 100 ))"; then pass "video \"Done\" shows only the cropped part ($render of $source_size)"; else fail "video cropped preview" "$cropped_state"; fi
click_control "Crop" >/dev/null
wait_for_text 10 "tool=crop" video_state
click_control "Reset" >/dev/null
wait_for_text 10 "crop=none" video_state
click_control "Done" >/dev/null
wait_for 10 video_field_is tool select
# The preview re-renders for the whole frame again.
whole_frame_rendered() { local state; state=$(video_state); [ "$(vfield "$state" render)" = "$(vfield "$state" source)" ]; }
wait_for 10 whole_frame_rendered
reset_state=$(video_state)
if [ "$(vfield "$reset_state" crop)" = "none" ] && [ "$(vfield "$reset_state" render)" = "$(vfield "$reset_state" source)" ]; then pass "video \"Reset\" keeps the whole frame again"; else fail "video reset the crop" "$reset_state"; fi
# Text by a click, typed right on the video: a click with Text used to play the video instead.
area_at() { awk "BEGIN { printf \"%d,%d,%d,%d\", $sx + $sw * $1, $sy + $sh * $2, $sw * $3, $sh * $4 }"; }
$R video-seek:2 10 >/dev/null
click_control "Text" >/dev/null
wait_for 5 video_field_is tool text
$R "post-click:$(at 0.3 0.3)" 10 >/dev/null
wait_for_text 10 "typing=true" video_state
placed=$(video_state)
$R post-text:Total 10 >/dev/null
$R post-key:36:none 10 >/dev/null
video_typed() { local shown; shown=$(video_state); [[ "$shown" == *"lastText=Total"* && "$shown" == *"typing=false"* ]]; }
wait_for 10 video_typed
typed=$(video_state)
if [ "$(vfield "$placed" lastKind)" = "text" ] && [ "$(vfield "$placed" typing)" = "true" ] && [ "$(vfield "$typed" lastText)" = "Total" ] && [ "$(vfield "$typed" typing)" = "false" ] && [ "$(vfield "$typed" playing)" = "false" ]; then pass "video a click with Text places text and it is typed right on the video"; else fail "video text by a click" "$placed / $typed"; fi
text_pixels=$(vfield "$($R "screen-color:$(area_at 0.27 0.27 0.2 0.12):$(vfield "$typed" lastColor)" 20)" coral)
if [ "$(vfield "$typed" typing)" = "false" ] && [ "${text_pixels:-0}" -gt 150 ] 2>/dev/null; then pass "video the typed text shows on the video in the editor"; else fail "video text not shown" "$text_pixels"; fi
# An arrow drawn with the mouse shows in the editor window, not only in the saved file.
click_control "Arrow" >/dev/null
wait_for 5 video_field_is tool arrow
arrow_front=$($R front-app 10)
arrow_hit=$($R "windows-at:$(at 0.55 0.3)" 10)
$R "post-drag:$(at 0.55 0.3):$(at 0.75 0.6)" 10 >/dev/null
# Real time: the arrow is drawn and the screen shows it before the pixels are counted.
sleep 1.5
arrow_state="front=$arrow_front windows=$arrow_hit $(video_state)"
arrow_pixels=$(vfield "$($R "screen-color:$(area_at 0.53 0.28 0.24 0.34):$(vfield "$arrow_state" lastColor)" 20)" coral)
if [ "${arrow_pixels:-0}" -gt 150 ] 2>/dev/null; then pass "video the arrow drawn shows on the video in the editor"; else fail "video arrow not shown in the editor" "$arrow_pixels $arrow_state"; fi
# Its bar on the timeline: the right edge makes it longer, the middle moves it.
bar_frame() { $R "control-frame:video:Bar: Arrow" 10 | sed -n 's/^frame=\([0-9-]*\),\([0-9-]*\) \([0-9]*\)x\([0-9]*\).*/\1 \2 \3 \4/p'; }
read -r bx by bw bh <<< "$(bar_frame)"
length_before=$(vfield "$arrow_state" lastLength)
if [ -n "$bx" ]; then
    $R "post-drag:$((bx + bw - 3)),$((by + bh / 2)):$((bx + bw + 60)),$((by + bh / 2))" 10 >/dev/null
    # Real time: the drag is handled; the state is read right after (also for "did not move" checks).
    sleep 0.8
fi
length_after=$(vfield "$(video_state)" lastLength)
if awk "BEGIN { exit !(${length_after:-0} > ${length_before:-0} + 0.5) }"; then pass "video a mark bar's right edge dragged makes the mark longer"; else fail "video bar edge" "frame=$bx,$by ${bw}x$bh length $length_before → $length_after"; fi
read -r bx by bw bh <<< "$(bar_frame)"
start_before=$(vfield "$(video_state)" lastStart)
if [ -n "$bx" ]; then
    $R "post-drag:$((bx + bw / 2)),$((by + bh / 2)):$((bx + bw / 2 + 50)),$((by + bh / 2))" 10 >/dev/null
    # Real time: the drag is handled; the state is read right after (also for "did not move" checks).
    sleep 0.8
fi
start_after=$(vfield "$(video_state)" lastStart)
if awk "BEGIN { exit !(${start_after:-0} > ${start_before:-0} + 0.3) }"; then pass "video a mark bar dragged in the middle moves the mark"; else fail "video bar move" "start $start_before → $start_after"; fi
press_in video: "Undo the last change (⌘Z)" >/dev/null
press_in video: "Undo the last change (⌘Z)" >/dev/null
press_in video: "Undo the last change (⌘Z)" >/dev/null
press_in video: "Undo the last change (⌘Z)" >/dev/null
$R video-seek:0 10 >/dev/null

$R video-range:1,8 10 >/dev/null
press_in video: "In" >/dev/null
$R video-range:8,9 10 >/dev/null
press_in video: "Out" >/dev/null
if [ "$(vfield "$(video_state)" trim)" = "1.0-8.0" ]; then pass "video \"In\" and \"Out\" trim at the playhead"; else fail "video in and out" "$(video_state)"; fi
$R video-range:3,4 10 >/dev/null
press_in video: "Cut" >/dev/null
cuts=$(vfield "$(video_state)" cuts)
press_in video: "Undo the last change (⌘Z)" >/dev/null
undone=$(vfield "$(video_state)" cuts)
press_in video: "Redo what was undone (⇧⌘Z)" >/dev/null
if [ "$cuts" = 1 ] && [ "$undone" = 0 ] && [ "$(vfield "$(video_state)" cuts)" = 1 ]; then pass "video \"Cut\" cuts the range, \"Undo\" and \"Redo\" take it back and again"; else fail "video cut, undo, redo" "$cuts $undone"; fi
$R video-range:5,6 10 >/dev/null
press_in video: "Slow-mo" >/dev/null
press_in video: "Freeze" >/dev/null
if [ "$(vfield "$(video_state)" speeds)" = 1 ] && [ "$(vfield "$(video_state)" freezes)" = 1 ]; then pass "video \"Slow-mo\" and \"Freeze\" add slow motion and a still frame"; else fail "video slow-mo and freeze" "$(video_state)"; fi

for row in "Text|text" "Arrow|arrow" "Box|rectangle" "Blur|blur"; do
    label="${row%%|*}"
    tool="${row##*|}"
    press_in video: "$label" >/dev/null
    picked=$(vfield "$(video_state)" tool)
    press_in video: "$label" >/dev/null
    if [ "$picked" = "$tool" ] && [ "$(vfield "$(video_state)" tool)" = select ]; then pass "video \"$label\" picks the tool, pressing again puts it down"; else fail "video tool \"$label\"" "$picked"; fi
done

for row in "Highlight clicks|clicks" "Show keystrokes|keys" "Show steps|steps" "Environment badge|badge"; do
    label="${row%%|*}"
    key="${row##*|}"
    first=$(vfield "$(video_state)" "$key")
    press_in video: "$label" >/dev/null
    second=$(vfield "$(video_state)" "$key")
    press_in video: "$label" >/dev/null
    if [ "$first" != "$second" ] && [ "$(vfield "$(video_state)" "$key")" = "$first" ]; then pass "video switch \"$label\" turns on and off"; else fail "video switch \"$label\"" "$first $second"; fi
done

$R video-add-overlay:text 10 >/dev/null
scale=$(vfield "$(video_state)" scale)
press_in video: "Bigger mark" >/dev/null
bigger=$(vfield "$(video_state)" scale)
press_in video: "Smaller mark" >/dev/null
if [ "$bigger" != "$scale" ] && [ "$(vfield "$(video_state)" scale)" = "$scale" ]; then pass "video \"Bigger mark\" and \"Smaller mark\" resize the selected mark"; else fail "video mark size" "$scale $bigger"; fi
# The toolbar's size control says "text size" for the selected text and resizes it too.
press_in video: "Bigger text size" >/dev/null
bigger=$(vfield "$(video_state)" scale)
press_in video: "Smaller text size" >/dev/null
if [ "$bigger" != "$scale" ] && [ "$(vfield "$(video_state)" scale)" = "$scale" ]; then pass "video \"Bigger text size\" and \"Smaller text size\" in the toolbar: the toolbar size resizes the selected text"; else fail "video toolbar size" "$scale $bigger"; fi
# The selected text's background: a segmented switch, Label or Transparent.
clear_before=$(vfield "$(video_state)" clear)
press_in video: Transparent >/dev/null
clear_on=$(vfield "$(video_state)" clear)
press_in video: Label >/dev/null
if [ "$clear_before" = false ] && [ "$clear_on" = true ] && [ "$(vfield "$(video_state)" clear)" = false ]; then pass "video text \"Transparent\" and \"Label\" switch the text background"; else fail "video text background" "$clear_before $clear_on"; fi
# Corner shows only with the environment badge on, so the badge goes on for it and back after.
badge_was=$(vfield "$(video_state)" badge)
if [ "$badge_was" != true ]; then press_in video: "Environment badge" >/dev/null; fi
for label in "Corner" "Quality" "Size limit"; do
    result=$(picker_round_trip video "$label")
    if [[ "$result" == ok* ]]; then pass "video picker \"$label\" picks another choice and back (${result#ok })"; else fail "video picker \"$label\"" "$result"; fi
done
if [ "$badge_was" != true ]; then press_in video: "Environment badge" >/dev/null; fi

printf '' | pbcopy
press_in video: "Copy" >/dev/null
if pbpaste | grep -q "Environment"; then pass "video environment \"Copy\" puts the environment on the clipboard"; else fail "video environment copy"; fi
$R settings-page:General 10 >/dev/null
edit_result=$(press_in video: Edit)
# Opened for the first time in a run, Settings lists its controls after a moment, on the Bug reports page.
wait_for_text 5 "|Include Device" $R controls:settings 30
shown=$($R controls:settings 30)
if [ "$edit_result" = "pressed" ] && [[ "$shown" == *"|Include Device"* ]]; then pass "video \"Edit\" next to Environment opens Settings on Bug reports"; else fail "video Edit environment" "$edit_result windows=$(windows_now) edits=$($R controls:video 30 | sed 's/ ;; /\n/g' | grep -c '|Edit$') settings=$($R controls:settings 30 | cut -c1-200)"; fi
report_start=$(setting_value bugReportFormat)
printf '' | pbcopy
$R "choose:video:Copy bug report as => Copy as Markdown" 10 >/dev/null
as_markdown=$(pbpaste | grep -c "^## Steps to reproduce")
printf '' | pbcopy
press_in video: "Copy bug report · Markdown" >/dev/null
again_markdown=$(pbpaste | grep -c "^## Steps to reproduce")
remembered=$(setting_value bugReportFormat)
$R "setting-write:bugReportFormat=$report_start" 10 >/dev/null
printf '' | pbcopy
if [ "$as_markdown" = 1 ] && [ "$again_markdown" = 1 ] && [ "$remembered" = Markdown ] && [ "$(setting_value bugReportFormat)" = "$report_start" ]; then pass "video \"Copy bug report\" copies the report, its arrow picks the format"; else fail "video copy bug report" "$report_start: md=$as_markdown click=$again_markdown"; fi
press_in video: "GIF" >/dev/null
gif=$(vfield "$(video_state)" format)
gif_rate=$($R control-value:video:"GIF frame rate" 10)
result=$(picker_round_trip video "GIF frame rate")
if [[ "$result" == ok* ]]; then pass "video picker \"GIF frame rate\" picks another choice and back (${result#ok })"; else fail "video picker \"GIF frame rate\"" "$result"; fi
press_in video: "MP4" >/dev/null
if [ "$gif" = GIF ] && [ "$(vfield "$(video_state)" format)" = MP4 ] && [[ "$gif_rate" == value=*fps* ]]; then pass "video \"GIF\" and \"MP4\" switch the format, GIF shows its frame rate"; else fail "video format" "$gif $gif_rate"; fi
press_in video: "Save to folder" >/dev/null
# The file appears while the export still writes it; the editor shows it in Finder once it is written.
wait_for 60 dir_has_file "$out_dir"
wait_for_text 30 "reveal $out_dir/" $R system-actions:read 10
saved=$(ls "$out_dir" | head -1)
if [[ "$saved" == *.mp4 ]] && $R system-actions:read 10 | grep -q "reveal $out_dir/"; then pass "video \"Save to folder\" exports the edited clip ($saved)"; else fail "video save to folder" "$saved"; fi
printf '' | pbcopy
press_in video: "Copy MP4" >/dev/null
# The export takes a while.
wait_for_text 60 "file-url" $R pasteboard-types 10
if $R pasteboard-types 10 | grep -q "file-url"; then pass "video \"Copy MP4\" puts the exported file on the clipboard"; else fail "video copy file" "$($R pasteboard-types 10)"; fi
printf '' | pbcopy
$R system-actions:stop 10 >/dev/null
# The next clip opens with the choices changed here: GIF and the keystrokes switch.
press_in video: "GIF" >/dev/null
press_in video: "Show keystrokes" >/dev/null
left=$(video_state)
$R close-windows 10 >/dev/null
$R save:5 60 >/dev/null
wait_for_text 10 "video:" windows_now
opened=$(video_state)
if [ "$(vfield "$opened" format)" = GIF ] && [ "$(vfield "$opened" keys)" = "$(vfield "$left" keys)" ]; then pass "a new clip opens with the last format and switches"; else fail "video editor memory" "$left / $opened"; fi
press_in video: "MP4" >/dev/null
press_in video: "Show keystrokes" >/dev/null
$R close-windows 10 >/dev/null
$R "setting-write:outputFolderPath=$saved_output" 10 >/dev/null

section "the bear stays in sight"
# On a Mac with a notch a new menu bar item goes leftmost and macOS hides it behind the notch.
probe=$($R status-item-probe 10)
if [[ "$probe" == *"occlusionVisible=true"* ]]; then pass "the bear is visible after launch ($probe)"; else fail "the bear is visible after launch" "$probe"; fi
result=$($R menubar-hide-and-recover 30)
if [[ "$result" == "notch=true hiddenBefore=false"* ]]; then
    # The menu bar has room for it even at the far left: nothing hides it, nothing to recover.
    echo "SKIP  the bear could not be hidden behind the notch here ($result)"
elif [[ "$result" == "notch=true hiddenBefore=true hiddenAfter=false"* || "$result" == "notch=false "*"hiddenAfter=false"* ]]; then pass "a bear hidden behind the notch is moved back into sight ($result)"; else fail "the bear is moved back into sight" "$result"; fi
# ⌥⇧B opens the menu, also when the bear is hard to reach.
$R close-panel 10 >/dev/null
$R post-key:11:option,shift 10 >/dev/null
wait_for 10 menu_panel_open
if $R windows-debug 10 | tr '|' '\n' | grep "MenuBarExtraWindow" | grep -q "visible=true"; then pass "⌥⇧B opens the $APP_NAME menu"; else fail "⌥⇧B opens the $APP_NAME menu"; fi
$R close-panel 10 >/dev/null

section "tooltips"
# Hover a toolbar button in the screenshot editor, and a tab in the menu panel with the app not
# active (how the panel is used): a tooltip appears in both.
$R screenshot-full 40 >/dev/null
wait_for_text 10 "Save to folder" $R controls:screenshot: 30
result=$($R "tooltip-probe:screenshot,120,82" 15)
if echo "$result" | grep -q "tooltips=1"; then pass "tooltip on an editor tool"; else fail "tooltip on an editor tool" "$result"; fi
result=$($R editor-checks 30)
editor_checks="$result"
if echo "$result" | grep -q "sizeFollowsTool=true"; then pass "one size control: text size for text, line width for shapes"; else fail "size control" "$result"; fi
if echo "$result" | grep -q "sizeFollowsSelection=true"; then pass "the size control shows and changes the selected mark"; else fail "size control with a selection" "$result"; fi
if echo "$result" | grep -q "typingNoFillAtOnce=true"; then pass "No fill takes the label off text while typing"; else fail "No fill while typing" "$result"; fi
if echo "$result" | grep -q "textDrawnOnce=true"; then pass "text being typed is drawn once, not twice"; else fail "text drawn twice while typing" "$result"; fi
if echo "$result" | grep -q "defaultLine=true"; then pass "a new screenshot editor draws at size 7"; else fail "default line size 7" "$result"; fi
if echo "$result" | grep -q "pasteImage=true"; then pass "⌘V places a picture on the screenshot"; else fail "paste a picture" "$result"; fi
if echo "$result" | grep -q "calloutTyping=true"; then pass "arrow with text opens its note for typing as soon as it is drawn"; else fail "arrow with text typing" "$result"; fi
if echo "$result" | grep -q "calloutEmptyIsArrow=true"; then pass "arrow with text left empty stays as a plain arrow"; else fail "arrow with text left empty" "$result"; fi
# A real ⌘V, also with a non-Latin keyboard layout (V types "м" in Russian).
for focus in canvas elsewhere; do
    result=$($R "editor-paste-key:$focus" 20)
    if [[ "$result" == "added=1 picture=true"* ]]; then pass "a real ⌘V pastes a picture with the focus on the $focus ($result)"; else fail "a real ⌘V pastes a picture ($focus)" "$result"; fi
done
if echo "$editor_checks" | grep -q "deleteInEditorWindow=true"; then pass "Delete in the editor window removes the selected mark with the focus away from the canvas"; else fail "Delete key" "$editor_checks"; fi
$R close-windows 10 >/dev/null
$R press-status-item 10 >/dev/null
wait_for_text 10 "|Recent" $R controls:menubar 30
result=$($R "tooltip-probe:menubar,40,175" 15)
if echo "$result" | grep -q "active=false tooltips=1"; then pass "tooltip in the menu panel while the app is not active"; else fail "tooltip in the menu panel" "$result"; fi
$R close-panel 10 >/dev/null

section "what's new"
$R whats-new 10 >/dev/null
if $R windows-debug 10 | tr '|' '\n' | grep "visible=true" | grep -q "720x"; then pass "What's New window opens"; else fail "What's New window"; fi
$R close-windows 10 >/dev/null

section "welcome guide fits the screen"
# Opened fresh, the guide keeps its own size and stays inside the screen, so Continue is reachable.
frame_key="NSWindow Frame Window.onboarding"
defaults delete "$BUNDLE_ID" "$frame_key" 2>/dev/null
result=$($R open-onboarding 10)
if python3 scripts/test/lib/window-fits.py "$result"; then pass "welcome guide fits the screen ($result)"; else fail "welcome guide fits the screen" "$result"; fi
$R close-windows 10 >/dev/null
defaults delete "$BUNDLE_ID" "$frame_key" 2>/dev/null

section "report a problem"
for kind in problem idea; do
    result=$($R "open-feedback:$kind" 10)
    if [[ "$result" == "opened inside=true"* ]]; then pass "the $kind window opens on screen ($result)"; else fail "the $kind window opens on screen" "$result"; fi
done
result=$($R feedback-url:problem 15)
length=$(echo "$result" | sed -n 's/.*length=\([0-9]*\).*/\1/p')
log_count=$(echo "$result" | sed -n 's/.*logs=\([0-9]*\).*/\1/p')
if [[ "$result" == "template=bug_report.yml version=true "*" planted=true "*" home=false user=false" ]] && (( log_count > 0 && log_count <= 80 && length <= 5500 )); then pass "a problem link fills the form with the version and the newest log lines, hides the home folder and user name ($result)"; else fail "a problem link fills the form" "$result"; fi
result=$($R feedback-url:idea 15)
if [[ "$result" == "template=feature_request.yml version=true logs=0 "*" home=false user=false" ]]; then pass "an idea link uses the idea form without logs ($result)"; else fail "an idea link uses the idea form" "$result"; fi
result=$($R feedback-zip 20)
if [[ "$result" == *"$APP_NAME.log"* && "$result" == *"environment.txt"* && "$result" == *"planted=true home=false user=false" ]]; then pass "the log zip has the log and the environment, hides the home folder and user name ($result)"; else fail "the log zip" "$result"; fi
result=$($R feedback-crash:on 15)
if [[ "$result" == "offered=true open=true crash=true canSend=true moved=true title=$APP_NAME quit unexpectedly" ]]; then pass "a crash since the last launch opens a report with the crash filled in ($result)"; else fail "a crash opens a report" "$result"; fi
result=$($R feedback-crash:off 15)
if [[ "$result" == "offered=false open=false crash=false canSend=false moved=true title=" ]]; then pass "with crash reports turned off nothing opens, and the crash is not offered later ($result)"; else fail "crash reports turned off" "$result"; fi
result=$($R feedback-switch 10)
if [[ "$result" == "kind=idea" ]]; then pass "asking for an idea while the problem window is open shows the idea form"; else fail "switching the feedback window" "$result"; fi

section "disk space"
fixture="$WORK/space"
mkdir -p "$fixture/videos" "$fixture/notes"
# Real data, not sparse files: the scan counts what is allocated on disk. "Largest files" lists 50 MB and up.
head -c 60000000 /dev/urandom >"$fixture/videos/big.mov"
head -c 5000000 /dev/urandom >"$fixture/videos/small.mov"
head -c 1000000 /dev/urandom >"$fixture/notes/a.txt"
relative="${fixture#"$HOME"/}"
result=$($R "space-scan:$relative" 90)
if echo "$result" | grep -q "^files=3 "; then pass "scan counts the files ($(echo "$result" | cut -d' ' -f1-2))"; else fail "scan" "$result"; fi
folder=$($R "space-folder:$relative > videos" 10)
if echo "$folder" | grep -q "videos=6[45]"; then pass "folder sizes ($folder)"; else fail "folder sizes" "$folder"; fi
top=$($R space-top:1 10)
if echo "$top" | grep -q "big.mov"; then pass "largest file first"; else fail "largest file" "$top"; fi
# The stopped scan is of videos (2 files), the new one of notes (1 file): a stale result would say 2.
result=$($R "space-stop-test:$relative/videos:$relative/notes" 60)
if echo "$result" | grep -q "afterStop=idle final=done.* files=1$"; then pass "stopped scan leaves no stale result"; else fail "stop scan" "$result"; fi
rm -rf "$fixture"
result=$($R space-clean-test 60)
if echo "$result" | grep -q "cacheGone=true homebrewKept=true otherLogGone=true ownLogKept=true cachesFolderKept=true crashReportsKept=true"; then pass "clean-up deletes caches and keeps what it must"; else fail "clean-up" "$result"; fi
result=$($R space-measure 120)
if echo "$result" | grep -q "^free="; then pass "categories measured"; else fail "measure" "$result"; fi
$R open-space:Folders 10 >/dev/null
wait_for 10 window_open space
if $R windows-debug 10 | tr '|' '\n' | grep "visible=true" | grep -q "level=0"; then pass "Space window opens"; else fail "Space window"; fi
$R close-windows 10 >/dev/null

# Close the test page window, and only that one.
$R "activate-app:$BROWSER" 10 >/dev/null
if $R front-title 10 | grep -q "^title=Scroll test"; then
    $R post-key:13:cmd 10 >/dev/null
fi

$R setting:readBrowserURL:true 10 >/dev/null
$R browser-accessibility-off 10 >/dev/null

section "quitting stops the screen capture"
# pkill (updates, reinstalls) used to end the app mid-capture, and macOS kept showing
# "<name> - Currently Sharing" after it was gone.
$R buffer-start 30 >/dev/null
log_lines_before=$(wc -l < "$LOG")
pkill -x "$APP_NAME" 2>/dev/null
# It has to quit by itself: wait_for_app_to_quit would end it with kill -9 and hide a hang.
waited=0
while pgrep -x "$APP_NAME" >/dev/null && [ "$waited" -lt 30 ]; do
    # Poll step.
    sleep 0.2
    waited=$((waited + 1))
done
if pgrep -x "$APP_NAME" >/dev/null; then quit_by_itself=false; else quit_by_itself=true; fi
wait_for_app_to_quit
quit_log=$(tail -n +"$((log_lines_before + 1))" "$LOG")
if [ "$quit_by_itself" = true ]; then pass "$APP_NAME quits on SIGTERM"; else fail "$APP_NAME quits on SIGTERM" "still running after 6 s"; fi
if echo "$quit_log" | grep -q "quit requested by SIGTERM" && echo "$quit_log" | grep -q "capture stopped for quit" && ! echo "$quit_log" | grep -q "quit timed out" && ! echo "$quit_log" | grep -q "quit did not finish"; then pass "SIGTERM stops the screen capture before quitting"; else fail "SIGTERM stops the screen capture" "$quit_log"; fi

defaults write "$BUNDLE_ID" automationEnabled -bool false
# The app has quit above, so its captures can go from disk; it reads the folder on the next launch.
removed=0
while IFS= read -r folder_name; do
    if [ -z "$folder_name" ] || grep -qxF "$folder_name" "$WORK/captures-before.txt"; then continue; fi
    rm -rf "${CAPTURES_DIR:?}/$folder_name"
    removed=$((removed + 1))
done < <(ls "$CAPTURES_DIR" 2>/dev/null)
echo "removed $removed captures the tests made"
pbcopy < "$WORK/clipboard-before.txt"
if [ "$(defaults read "$BUNDLE_ID" recentAnnotationColors 2>/dev/null)" = "$(cat "$WORK/palette-before.txt")" ]; then pass "the tests leave the person's editor colors as they were"; else fail "editor colors changed by the tests" "$(defaults read "$BUNDLE_ID" recentAnnotationColors 2>/dev/null | tr -d '\n ')"; fi
print_section_times
echo
echo "$PASSES passed, $FAILURES failed."
[ "$FAILURES" = "0" ]
