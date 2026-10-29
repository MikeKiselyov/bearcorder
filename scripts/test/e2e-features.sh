#!/bin/bash
# Real-screen checks of the features that need other apps and the mouse: scrolling screenshot of a
# browser page, window resizing, ruler, color picker, design overlay, area recording through the
# picker, shortcuts, reports, step guide, comparison, editor sizes.
#
#   scripts/test/e2e-features.sh                     # in Google Chrome
#   E2E_BROWSER=Safari scripts/test/e2e-features.sh  # or another browser
#
# Opens a local test page in a new browser window and moves the mouse; don't touch the Mac while it runs (~2 min).
# Needs Screen Recording and Accessibility for Bugbear. Restores the settings it changes.
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
R=scripts/dev/bugbear-run.sh
BROWSER="${E2E_BROWSER:-Google Chrome}"
WORK="$ROOT/build/e2e-features"
FAILURES=0
PASSES=0

pass() { echo "PASS  $1"; PASSES=$((PASSES + 1)); }
fail() { echo "FAIL  $1 ${2:-}"; FAILURES=$((FAILURES + 1)); }
field() { echo "$1" | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }
# shellcheck disable=SC1091
source "$ROOT/scripts/test/lib/e2e-helpers.sh"

echo "==> build and launch"
scripts/build-app.sh >/dev/null 2>&1 || { echo "build failed"; exit 1; }
# Quit the person's Bugbear and keep a copy of their settings before any test setting is written.
quit_running_bugbear
rm -rf "$WORK"
mkdir -p "$WORK"
defaults write "$BUNDLE_ID" automationEnabled -bool true
# What the tests leave behind is cleaned up at the end: the captures they made (folders that were
# not there before) and the text on the clipboard.
CAPTURES_DIR="$HOME/Library/Application Support/Bugbear/Captures"
ls "$CAPTURES_DIR" 2>/dev/null | sort > "$WORK/captures-before.txt"
# Editor choices made by the tests go to a store of their own (EditorMemory); start it empty.
defaults delete "$BUNDLE_ID.tests" 2>/dev/null
pbpaste > "$WORK/clipboard-before.txt" 2>/dev/null
# The person's editor palette; the tests pick colors in a store of their own.
defaults read "$BUNDLE_ID" recentAnnotationColors > "$WORK/palette-before.txt" 2>/dev/null

echo "==> a new install shows the welcome guide"
# Settings outlive a deleted app, so installing where no Bugbear is starts the guide again;
# installing over a copy (an update) keeps them.
# The test copy shares the installed app's settings: keep what these steps touch and put it back.
saved_onboarding=$(defaults read "$BUNDLE_ID" onboardingCompleted 2>/dev/null || echo "")
saved_onboarding_page=$(defaults read "$BUNDLE_ID" onboardingPage 2>/dev/null || echo "")
saved_whats_new=$(defaults read "$BUNDLE_ID" whatsNewLastSeenID 2>/dev/null || echo "")
install_dir="$WORK/apps"
defaults write "$BUNDLE_ID" onboardingCompleted -bool true
BUGBEAR_INSTALL_DIR="$install_dir" BUGBEAR_NO_OPEN=1 scripts/build-app.sh --install >/dev/null 2>&1
if ! defaults read "$BUNDLE_ID" onboardingCompleted >/dev/null 2>&1; then pass "installing where no Bugbear is forgets the finished guide"; else fail "a new install forgets the finished guide"; fi
defaults write "$BUNDLE_ID" onboardingCompleted -bool true
BUGBEAR_INSTALL_DIR="$install_dir" BUGBEAR_NO_OPEN=1 scripts/build-app.sh --install >/dev/null 2>&1
if [ "$(defaults read "$BUNDLE_ID" onboardingCompleted 2>/dev/null)" = "1" ]; then pass "installing over a copy (an update) keeps the finished guide"; else fail "an update keeps the finished guide"; fi
rm -rf "$install_dir"
defaults delete "$BUNDLE_ID" onboardingCompleted 2>/dev/null
defaults write "$BUNDLE_ID" automationFirstLaunch -bool true
open "$TEST_APP"
sleep 6
result=$($R window-visible:onboarding 10)
if [ "$result" = "visible=true" ]; then pass "the first launch opens the welcome guide"; else fail "the first launch opens the welcome guide" "$result"; fi
pkill -x Bugbear 2>/dev/null
wait_for_bugbear_to_quit
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
sleep 6
$R setting:readBrowserURL:false 10 >/dev/null
# The launch looks for a crash of the last run (no window in test runs) and remembers when it looked.
if defaults read "$BUNDLE_ID" feedbackLastCrashCheck >/dev/null 2>&1; then pass "launch checks for a crash of the last run"; else fail "launch checks for a crash of the last run" "feedbackLastCrashCheck not set"; fi
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
        f'<header>Bugbear scroll test · sticky header</header>{"".join(rows)}<footer>Sticky footer · end of page</footer></body></html>')
open(sys.argv[1], "w").write(html)
EOF
# A new window, so the browser windows you have open are not moved or resized.
case "$BROWSER" in
    *Chrome*|*Chromium*|*Edge*|*Brave*)
        # Chromium browsers open the page in a new window of the usual profile; nothing is typed into
        # whatever browser window happened to be in front.
        open -na "$BROWSER" --args --new-window "file://$WORK/long.html"
        sleep 4
        $R "activate-app:$BROWSER" 10 >/dev/null
        sleep 1
        ;;
    *)
        $R "activate-app:$BROWSER" 10 >/dev/null
        sleep 1
        front=$($R screen 10 | sed -n 's/.*front=//p')
        if [ "$front" = "$BROWSER" ]; then
            $R post-key:45:cmd 10 >/dev/null
            sleep 1.5
            printf '%s' "file://$WORK/long.html" | pbcopy
            $R post-key:37:cmd 10 >/dev/null
            sleep 0.3
            $R post-key:9:cmd 10 >/dev/null
            sleep 0.3
            $R post-key:36:none 10 >/dev/null
            sleep 3
        else
            # Other browsers ignore --new-window; they open the page in a window of their own choice.
            open -a "$BROWSER" "file://$WORK/long.html"
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

echo "==> window size"
stop_unless_test_page
result=$($R resize-front:1280x720 10)
if echo "$result" | grep -q "app=$BROWSER size=1280x720"; then pass "resize $BROWSER to 1280×720"; else fail "resize $BROWSER" "$result"; fi
stop_unless_test_page
$R resize-front:1100x760 10 >/dev/null
sleep 1

echo "==> scrolling screenshot"
stop_unless_test_page
$R post-key:115:none 10 >/dev/null
sleep 1
# The page area from Accessibility: normalized on its display, global frame, display width.
# Chrome builds its accessibility tree for a page on the first requests, so ask a few times.
web=""
for _ in 1 2 3 4 5; do
    web=$($R web-area 10)
    if [ "$web" != "no web area" ] && [ -n "$web" ]; then
        break
    fi
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

echo "==> color picker"
( $R pick-color-test 30 > "$WORK/pick.txt" ) &
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

echo "==> ruler"
$R ruler-start 10 >/dev/null
$R post-drag:400,300:700,500 10 >/dev/null
$R "activate-app:$BROWSER" 10 >/dev/null
sleep 1
stop_unless_test_page
$R post-key:53:none 10 >/dev/null
sleep 1
if [ "$($R ruler-state 10)" = "active=false" ]; then pass "Esc closes the ruler even with $BROWSER in front"; else fail "ruler Esc"; $R ruler-stop 10 >/dev/null; fi

echo "==> design overlay"
result=$($R overlay-test:2 20)
if echo "$result" | grep -q "frame=700x400 alpha=0.40"; then pass "1400 px design at @2x is 700×400 pt"; else fail "overlay size" "$result"; fi
result=$($R overlay-click-through:true 10)
if echo "$result" | grep -q "clickThrough=true"; then pass "overlay click-through"; else fail "overlay click-through" "$result"; fi
$R overlay-close 10 >/dev/null

echo "==> area recording through the picker"
$R "activate-app:$BROWSER" 10 >/dev/null
sleep 1
$R record-area-picker 10 >/dev/null
sleep 1.5
chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
$R "post-click:$chip" 10 >/dev/null
sleep 0.5
$R post-key:36:none 10 >/dev/null
sleep 3
result=$($R recording-region 10)
# One outline window per display: a frame on this one, "Not recorded" on the others.
screen_count=$($R screens 10 | tr ';' '\n' | wc -l | tr -d ' ')
if echo "$result" | grep -q "region=640x360 recording=true outline=$screen_count"; then pass "720p chip picks 640×360 pt and shows the outline on $screen_count display(s)"; else fail "area picker" "$result"; fi
sleep 2
$R record-stop 60 >/dev/null
result=$($R "frame-of-latest:1:$WORK/area-frame.png" 30)
if [ "$result" = "frame=1280x720" ]; then pass "area clip is 1280×720"; else fail "area clip size" "$result"; fi
$R close-windows 10 >/dev/null

echo "==> resizing the area while recording"
# The frame has handles: dragging the bottom-right one makes the area bigger, and the clip gets
# the area as it is when the recording stops.
$R "activate-app:$BROWSER" 10 >/dev/null
sleep 1
$R record-area-picker 10 >/dev/null
sleep 1.5
chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
$R "post-click:$chip" 10 >/dev/null
sleep 0.5
$R post-key:36:none 10 >/dev/null
sleep 3
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
sleep 1
result=$($R recording-region 10)
if echo "$result" | grep -q "region=740x410 recording=true"; then pass "dragging the corner while recording makes the area 740×410 pt"; else fail "resize the area while recording" "$result"; fi
moved=$($R area-handles 10 | cut -d';' -f2)
if [ "$moved" = "$((corner_x + 100)),$((corner_y + 50))" ]; then pass "the handle follows the frame"; else fail "the handle follows the frame" "$moved, expected $((corner_x + 100)),$((corner_y + 50))"; fi
front=$($R front-app 10)
if [ "$front_before" = "$BROWSER" ] && [ "$front" = "$BROWSER" ]; then pass "dragging a handle leaves $BROWSER in front"; else fail "dragging a handle took the focus" "before=$front_before after=$front"; fi
sleep 2
$R record-stop 60 >/dev/null
result=$($R "frame-of-latest:1:$WORK/area-resized.png" 30)
if [ "$result" = "frame=1480x820" ]; then pass "the clip has the resized area, 1480×820"; else fail "resized area clip size" "$result"; fi
if [ -z "$($R area-handles 10)" ]; then pass "the handles go when the recording stops"; else fail "the handles go when the recording stops"; fi
$R close-windows 10 >/dev/null

echo "==> moving the area"
# In the picker a drag inside the area or by its grip moves it and an edge handle moves one side; while recording,
# the grip above the frame moves the whole area without resizing it, and the clip gets that place.
$R "activate-app:$BROWSER" 10 >/dev/null
sleep 1
$R record-area-picker 10 >/dev/null
sleep 1.5
chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
$R "post-click:$chip" 10 >/dev/null
sleep 0.5
picked=$($R picker-selection 10)
IFS=, read -r pick_x pick_y pick_width pick_height <<< "$picked"
$R "post-drag:$((pick_x + pick_width / 2)),$((pick_y + pick_height / 2)):$((pick_x + pick_width / 2 + 100)),$((pick_y + pick_height / 2 + 60))" 15 >/dev/null
sleep 0.5
result=$($R picker-selection 10)
if [ "$result" = "$((pick_x + 100)),$((pick_y + 60)),$pick_width,$pick_height" ]; then pass "dragging inside the picked area moves it by 100,60 pt and keeps its size"; else fail "move the area in the picker" "$picked -> $result"; fi
pick_x=$((pick_x + 100))
pick_y=$((pick_y + 60))
$R "post-drag:$((pick_x + pick_width)),$((pick_y + pick_height / 2)):$((pick_x + pick_width + 80)),$((pick_y + pick_height / 2 + 40))" 15 >/dev/null
sleep 0.5
result=$($R picker-selection 10)
if [ "$result" = "$pick_x,$pick_y,$((pick_width + 80)),$pick_height" ]; then pass "the right edge handle in the picker makes the area 80 pt wider and nothing else"; else fail "edge handle in the picker" "$result"; fi
pick_width=$((pick_width + 80))
grip=$($R picker-grip 10)
grip_x=${grip%,*}
grip_y=${grip#*,}
result="no grip"
if [ -n "$grip" ]; then
    $R "post-drag:$grip_x,$grip_y:$((grip_x - 60)),$((grip_y + 40))" 15 >/dev/null
    sleep 0.5
    result=$($R picker-selection 10)
fi
if [ "$result" = "$((pick_x - 60)),$((pick_y + 40)),$pick_width,$pick_height" ]; then pass "the grip above the picked area moves it by -60,40 pt and keeps its size"; else fail "grip in the picker" "$grip: $result"; fi
pick_x=$((pick_x - 60))
pick_y=$((pick_y + 40))
$R post-key:36:none 10 >/dev/null
sleep 3
result=$($R recording-region 10)
if echo "$result" | grep -q "region=${pick_width}x${pick_height} recording=true .* at=$pick_x,$pick_y$"; then pass "the recording takes the moved and widened area"; else fail "area from the picker" "$result, expected ${pick_width}x${pick_height} at $pick_x,$pick_y"; fi
grip=$($R area-grip 10)
grip_x=${grip%,*}
grip_y=${grip#*,}
$R "post-drag:$grip_x,$grip_y:$((grip_x - 120)),$((grip_y + 50))" 15 >/dev/null
sleep 1
result=$($R recording-region 10)
if echo "$result" | grep -q "region=${pick_width}x${pick_height} recording=true .* at=$((pick_x - 120)),$((pick_y + 50))$"; then pass "dragging the grip while recording moves the area by -120,50 pt and keeps its size"; else fail "move the area while recording" "$result, expected at $((pick_x - 120)),$((pick_y + 50))"; fi
result=$($R area-grip 10)
if [ "$result" = "$((grip_x - 120)),$((grip_y + 50))" ]; then pass "the grip follows the frame"; else fail "the grip follows the frame" "$result"; fi
front=$($R front-app 10)
if [ "$front" = "$BROWSER" ]; then pass "dragging the grip leaves $BROWSER in front"; else fail "dragging the grip took the focus" "$front"; fi
sleep 2
$R record-stop 60 >/dev/null
result=$($R "frame-of-latest:1:$WORK/area-moved.png" 30)
if [ "$result" = "frame=$((pick_width * 2))x$((pick_height * 2))" ]; then pass "the clip of the moved area is $((pick_width * 2))×$((pick_height * 2))"; else fail "moved area clip size" "$result"; fi
if [ -z "$($R area-grip 10)" ]; then pass "the grip goes when the recording stops"; else fail "the grip goes when the recording stops"; fi
$R close-windows 10 >/dev/null

echo "==> an area across displays"
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
    sleep 1.5
    has_seam=0
    if seam_target; then has_seam=1; fi
    $R post-key:53:none 10 >/dev/null
    sleep 1
fi
if [ "$across_screens" -ge 2 ] && [ "$has_seam" = 0 ]; then
    echo "  (no display touches the one with the pointer: skipped)"
elif [ "$across_screens" -ge 2 ]; then
    $R "activate-app:$BROWSER" 10 >/dev/null
    sleep 1
    $R record-area-picker 10 >/dev/null
    sleep 1.5
    picker_count=$($R picker-screens 10 | tr ';' '\n' | grep -c ',')
    if [ "$picker_count" = "$across_screens" ]; then pass "the area picker covers all $across_screens displays"; else fail "picker on every display" "$picker_count of $across_screens"; fi
    chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
    $R "post-click:$chip" 10 >/dev/null
    sleep 0.5
    IFS=, read -r pick_x pick_y pick_width pick_height <<< "$($R picker-selection 10)"
    seam_target
    grip=$($R picker-grip 10)
    result="no grip"
    if [ -n "$grip" ]; then
        dx=$((target_x - (pick_x + pick_width / 2)))
        dy=$((target_y - (pick_y + pick_height / 2)))
        $R "post-drag:${grip%,*},${grip#*,}:$((${grip%,*} + dx)),$((${grip#*,} + dy))" 15 >/dev/null
        sleep 0.5
        result=$($R picker-selection 10)
    fi
    expected="$((target_x - pick_width / 2)),$((target_y - pick_height / 2)),$pick_width,$pick_height"
    if [ "$result" = "$expected" ]; then pass "the picker's grip puts the area across the seam of two displays"; else fail "area across displays in the picker" "$result, expected $expected"; fi
    $R post-key:36:none 10 >/dev/null
    sleep 3
    result=$($R recording-region 10)
    if echo "$result" | grep -q "region=${pick_width}x${pick_height} recording=true .* at=$((target_x - pick_width / 2)),$((target_y - pick_height / 2))$"; then pass "the recording takes the area across displays"; else fail "recording an area across displays" "$result"; fi
    sleep 2
    $R record-stop 60 >/dev/null
    result=$($R "frame-of-latest:1:$WORK/area-across.png" 30)
    if [ "$result" = "frame=$((pick_width * clip_scale))x$((pick_height * clip_scale))" ]; then pass "the clip across displays is $((pick_width * clip_scale))×$((pick_height * clip_scale)), the sharper display's density"; else fail "clip across displays size" "$result"; fi
    check_both_halves "$WORK/area-across.png" "picked across the seam"
    $R close-windows 10 >/dev/null

    # The same while recording: the area starts on one display, its grip takes it onto the seam.
    $R "activate-app:$BROWSER" 10 >/dev/null
    sleep 1
    $R record-area-picker 10 >/dev/null
    sleep 1.5
    chip=$($R picker-chips 10 | tr ';' '\n' | grep "^720p@" | cut -d@ -f2)
    $R "post-click:$chip" 10 >/dev/null
    sleep 0.5
    IFS=, read -r pick_x pick_y pick_width pick_height <<< "$($R picker-selection 10)"
    seam_target
    $R post-key:36:none 10 >/dev/null
    sleep 3
    grip=$($R area-grip 10)
    result="no grip"
    if [ -n "$grip" ]; then
        dx=$((target_x - (pick_x + pick_width / 2)))
        dy=$((target_y - (pick_y + pick_height / 2)))
        $R "post-drag:${grip%,*},${grip#*,}:$((${grip%,*} + dx)),$((${grip#*,} + dy))" 15 >/dev/null
        sleep 1
        result=$($R recording-region 10)
    fi
    if echo "$result" | grep -q "region=${pick_width}x${pick_height} recording=true .* at=$((target_x - pick_width / 2)),$((target_y - pick_height / 2))$"; then pass "the recording frame's grip moves the area onto the seam of two displays"; else fail "moving the area across displays while recording" "$result"; fi
    sleep 2
    $R record-stop 60 >/dev/null
    result=$($R "frame-of-latest:1:$WORK/area-moved-across.png" 30)
    if [ "$result" = "frame=$((pick_width * clip_scale))x$((pick_height * clip_scale))" ]; then pass "the clip of the area moved across displays is $((pick_width * clip_scale))×$((pick_height * clip_scale))"; else fail "moved across displays clip size" "$result"; fi
    check_both_halves "$WORK/area-moved-across.png" "moved across the seam"
    $R close-windows 10 >/dev/null
fi

echo "==> area picker buttons"
# The picker draws its buttons by hand; VoiceOver and the tests press them by name.
$R record-area-picker 10 >/dev/null
sleep 1.5
$R controls:region-picker 30 | sed 's/ ;; /\n/g' | sed "s#^#region-picker|#" > "$WORK/picker-controls.txt"
size_result=$(press_in region-picker "Size 720p")
record_result=$(press_in region-picker Record)
sleep 3
result=$($R recording-region 10)
if [ "$size_result" = "pressed" ] && [ "$record_result" = "pressed" ] && echo "$result" | grep -q "region=640x360 recording=true"; then pass "area picker \"Size\" chips and \"Record\" pressed by name record that area"; else fail "area picker buttons" "$size_result $record_result $result"; fi
$R record-stop 60 >/dev/null
$R close-windows 10 >/dev/null

echo "==> dock icon"
# The icon is in the Dock while a window is open. A click brings the window back; with no window
# left it opened nothing, so now the menu opens. macOS says where the app is:
# Foreground with a Dock icon, UIElement in the menu bar only.
dock_type() { lsappinfo info -only ApplicationType "$(pgrep -f "$TEST_APP/Contents/MacOS/$APP_NAME\$" | head -1)" 2>/dev/null | cut -d'"' -f4; }
$R close-windows 10 >/dev/null
$R open-space 30 >/dev/null
sleep 1
result=$($R dock-reopen 10)
in_dock=$(dock_type)
if [ "$(field "$result" windows)" = "1" ] && [ "$in_dock" = "Foreground" ] && [ "$(field "$result" menu)" = "false" ]; then pass "Dock icon click with a window open brings the window"; else fail "dock icon with a window" "$result $in_dock"; fi
$R close-windows 10 >/dev/null
sleep 0.5
result=$($R dock-reopen 10)
sleep 1.5
in_dock=$(dock_type)
# macOS 26 lets a process change its kind only once, so the icon may stay; a click on it then
# opens the menu, which is what has to work.
if [ "$(field "$result" windows)" = "0" ] && [ "$(field "$result" menu)" = "true" ]; then pass "Dock icon click with no window opens the menu ($in_dock)"; else fail "dock icon with no window" "$result $in_dock"; fi
$R close-panel 10 >/dev/null

echo "==> shortcuts"
LOG="$HOME/Library/Logs/Bugbear/bugbear.log"
before=$(grep -c "marker added" "$LOG")
$R post-key:46:option,shift 10 >/dev/null
sleep 1
if [ "$(grep -c "marker added" "$LOG")" -gt "$before" ]; then pass "⌥⇧M marks the moment"; else fail "⌥⇧M"; fi
$R hotkey-set:ruler:25:cmd,shift 10 >/dev/null
if $R hotkey-set:draw:19:option,shift 10 | grep -q "conflict with saveMinute"; then pass "a taken shortcut is refused"; else fail "shortcut conflict"; fi
$R post-key:25:cmd,shift 10 >/dev/null
sleep 1
if [ "$($R ruler-state 10)" = "active=true" ]; then pass "custom ⇧⌘9 opens the ruler"; else fail "custom shortcut"; fi
$R ruler-stop 10 >/dev/null
$R hotkey-reset 10 >/dev/null

echo "==> reports, guide, comparison, editors"
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

echo "==> several displays"
# wait_selected_screen <id> <seconds>: waits until the newest capture shows that display, prints the one shown.
wait_selected_screen() {
    local shown="" tries=0
    while [ "$tries" -lt $(($2 * 2)) ]; do
        shown=$($R clip-screens 10 | sed -n 's/^selected=\([^ ]*\) .*/\1/p')
        if [ "$shown" = "$1" ]; then break; fi
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

echo "==> menu panel"
$R close-panel 10 >/dev/null
if [ "$($R press-status-item 10)" = "open=true" ]; then pass "click on the bear opens the panel"; else fail "panel opens"; fi
if [ "$($R press-status-item 10)" = "open=false" ]; then pass "second click closes it"; else fail "panel closes"; fi
$R press-status-item 10 >/dev/null
$R screenshot-full 40 >/dev/null
$R close-windows 10 >/dev/null
if [ "$($R press-status-item 10)" = "open=true" ]; then pass "panel still opens after a screenshot"; else fail "panel after screenshot"; fi
$R close-panel 10 >/dev/null

echo "==> menu panel buttons: Capture"
# Every button is pressed the way VoiceOver presses it, and what it did is checked.
# With more than one display the menu offers "all displays" instead of "full screen".
display_count=$($R screens 10 | tr ';' '\n' | grep -c .)
full_screenshot="Screenshot full screen"
if [ "$display_count" -gt 1 ]; then full_screenshot="Screenshot all displays"; fi

for row in "30 s, ⌥⇧1|video:" "1 min, ⌥⇧2|video:" "3 min, ⌥⇧3|video:" "$full_screenshot|screenshot:"; do
    label="${row%%|*}"
    editor="${row##*|}"
    before=$(capture_count)
    result=$(press_menu Capture "$label")
    sleep 3
    after=$(capture_count)
    opened=$(windows_now)
    if [ "$result" = "pressed" ] && [ "$after" -eq $((before + 1)) ] && [[ "$opened" == *"$editor"* ]]; then pass "menu \"$label\" saves a capture and opens its editor"; else fail "menu \"$label\"" "$result before=$before after=$after windows=$opened"; fi
    $R close-windows 10 >/dev/null
done

# "Edit" next to the environment goes to Settings → Bug reports, from another page.
$R settings-page:General 10 >/dev/null
edit_result=$(press_menu Capture "Edit")
sleep 1
shown=$($R controls:settings 30)
if [ "$edit_result" = "pressed" ] && [[ "$shown" == *"|Include Device"* ]]; then pass "menu environment \"Edit\" opens Settings on Bug reports"; else fail "menu environment Edit" "$edit_result"; fi
$R close-windows 10 >/dev/null

# Area, window and text pick with the system's screencapture; cancelling saves nothing.
for label in "Screenshot area, ⌥⇧4" "Screenshot window, ⌥⇧5" "Copy text from screen, ⌥⇧O"; do
    before=$(capture_count)
    result=$(press_menu Capture "$label")
    sleep 1
    if pgrep -x screencapture >/dev/null; then picking=true; else picking=false; fi
    pkill -x screencapture 2>/dev/null
    sleep 1
    after=$(capture_count)
    if [ "$result" = "pressed" ] && [ "$picking" = true ] && [ "$after" -eq "$before" ]; then pass "menu \"$label\" starts picking, cancelling saves nothing"; else fail "menu \"$label\"" "$result picking=$picking before=$before after=$after"; fi
done

result=$(press_menu Capture "Scrolling screenshot")
sleep 1
picker=$(windows_now)
$R post-key:53:none 10 >/dev/null
sleep 1
if [ "$result" = "pressed" ] && [[ "$picker" == *"region-picker"* ]] && [[ "$(windows_now)" != *"region-picker"* ]]; then pass "menu \"Scrolling screenshot\" opens the area picker, Esc closes it"; else fail "menu \"Scrolling screenshot\"" "$result windows=$picker"; fi
result=$(press_menu Capture "Scrolling screenshot")
sleep 1
$R controls:region-picker 30 | sed 's/ ;; /\n/g' | sed "s#^#region-picker|#" >> "$WORK/picker-controls.txt"
cancel_result=$(press_in region-picker Cancel)
sleep 1
if [ "$cancel_result" = "pressed" ] && grep -q "|Capture$" "$WORK/picker-controls.txt" && [[ "$(windows_now)" != *"region-picker"* ]]; then pass "area picker \"Cancel\" closes it, the scrolling one says \"Capture\""; else fail "area picker Cancel" "$cancel_result $(windows_now)"; fi

result=$(press_menu Capture "Pause buffer")
sleep 1
paused=$($R status 10)
result_start=$(press_menu Capture "Start buffer")
sleep 3
running=$($R status 10)
if [[ "$paused" == paused* ]] && [[ "$running" == running* ]]; then pass "menu \"Pause buffer\" pauses it and \"Start buffer\" starts it again"; else fail "menu pause and start buffer" "$result/$result_start $paused / $running"; fi

for row in "Report a problem with $APP_NAME or suggest a feature on GitHub|feedback" "Open settings: buffer, shortcuts, storage and more|settings"; do
    label="${row%%|*}"
    window="${row##*|}"
    result=$(press_menu Capture "$label")
    sleep 1
    if [[ "$(windows_now)" == *"$window"* ]]; then pass "menu \"$label\" opens the $window window"; else fail "menu \"$label\"" "$result $(windows_now)"; fi
    $R close-windows 10 >/dev/null
done
$R close-panel 10 >/dev/null

echo "==> menu panel buttons: Record"
before=$(capture_count)
result=$(press_menu Record "Start recording")
sleep 3
started=$(tools_now)
paused_result=$(press_menu Record "Pause")
sleep 1
paused=$(tools_now)
resumed_result=$(press_menu Record "Resume")
sleep 1
resumed=$(tools_now)
stop_result=$(press_menu Record "Stop")
sleep 4
after=$(capture_count)
if [[ "$started" == *"recording=true paused=false"* ]]; then pass "menu \"Start recording\" records the full screen"; else fail "menu \"Start recording\"" "$result $started"; fi
if [[ "$paused" == *"recording=true paused=true"* && "$resumed" == *"recording=true paused=false"* ]]; then pass "menu \"Pause\" and \"Resume\" pause and resume the recording"; else fail "menu pause and resume" "$paused_result $paused / $resumed_result $resumed"; fi
if [ "$after" -eq $((before + 1)) ] && [[ "$(tools_now)" == *"recording=false"* ]]; then pass "menu \"Stop\" saves the recording"; else fail "menu \"Stop\"" "$stop_result before=$before after=$after"; fi
$R close-windows 10 >/dev/null

result=$(press_menu Record "Area…")
target=$(tools_now)
start_result=$(press_menu Record "Start recording")
sleep 1.5
picker=$(windows_now)
$R post-key:53:none 10 >/dev/null
sleep 1
not_started=$(tools_now)
# "All displays" when the app keeps every display.
full_label="Full screen"
if [ "$($R screens 10 | tr ';' '\n' | grep -c .)" -gt 1 ] && [ "$(setting_value captureAllDisplays)" = 1 ]; then full_label="All displays"; fi
full_result=$(press_menu Record "$full_label")
full=$(tools_now)
if [[ "$target" == *"target=area"* && "$picker" == *"region-picker"* && "$not_started" == *"recording=false"* && "$full" == *"target=screens"* ]]; then pass "menu \"Area…\" records a picked area, Esc cancels, \"$full_label\" switches back"; else fail "menu area and full screen" "$result $target / $start_result $picker / $not_started / $full_result $full"; fi

result=$(press_menu Record "Draw")
sleep 1
drawing=$(tools_now)
$R post-key:53:none 10 >/dev/null
sleep 0.5
if [[ "$drawing" == *"drawing=true"* && "$(tools_now)" == *"drawing=false"* ]]; then pass "menu \"Draw\" starts drawing on the screen, Esc ends it"; else fail "menu \"Draw\"" "$result $drawing"; fi
# Esc ends drawing, the marks stay until closed.
$R close-windows 10 >/dev/null

result=$(press_menu Record "Measure on screen")
sleep 1
measuring=$(tools_now)
$R ruler-stop 10 >/dev/null
if [[ "$measuring" == *"ruler=true"* ]]; then pass "menu \"Measure on screen\" opens the ruler"; else fail "menu \"Measure on screen\"" "$result $measuring"; fi

result=$(press_menu Record "Pick a color, copies hex")
sleep 1
picking=$(tools_now)
$R post-key:53:none 10 >/dev/null
sleep 0.5
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
    sleep 1
    after_value=$(setting_value "$setting")
    press_menu Record "$label" >/dev/null
    sleep 2
    back_value=$(setting_value "$setting")
    if [ "$before_value" != "$after_value" ] && [ "$before_value" = "$back_value" ]; then pass "menu \"$label\" turns $setting on and off"; else fail "menu \"$label\"" "$before_value → $after_value → $back_value"; fi
done
if [[ "$permissions" == *"camera=true"* ]]; then
    press_menu Record "Camera" >/dev/null
    sleep 2
    camera_on=$(windows_now)
    press_menu Record "Camera" >/dev/null
    sleep 1
    if [[ "$camera_on" == *"camera"* ]]; then pass "menu \"Camera\" shows the camera bubble"; else fail "menu \"Camera\"" "$camera_on"; fi
else
    echo "SKIP  menu \"Camera\": needs camera=true, macOS would ask"
fi
$R close-panel 10 >/dev/null

echo "==> menu panel buttons: Tools"
# Each chip opens the toolbox on its tool.
for row in "{ } JSON|JSON" "XML|XML" "YAML|YAML" "HTML|HTML" "SQL|SQL" "GraphQL|GraphQL" "JWT|JWT" "Base64|Base64" "URL|URL encode" "&; Entities|HTML entities" "Time|Time & dates" "Time zones|Time zones" "⇄ Convert|JSON ↔ YAML ↔ XML ↔ CSV" "0x · Color · Case|Numbers, colors, case" "UUID · Hash|UUID · hash" "Test data|Test data" "Regex|Regex" "QR|QR code"; do
    label="${row%%|*}"
    tool="${row##*|}"
    result=$(press_menu Tools "$label")
    sleep 1
    shown=$($R toolbox-tool 10)
    if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"toolbox"* ]] && [ "$shown" = "tool=$tool" ]; then pass "menu \"$label\" opens the toolbox on $tool"; else fail "menu \"$label\"" "$result $shown"; fi
done
$R close-windows 10 >/dev/null
printf '' | pbcopy
result=$(press_menu Tools "All tools")
sleep 1
if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"toolbox"* ]]; then pass "menu \"All tools\" opens the toolbox"; else fail "menu \"All tools\"" "$result $(windows_now)"; fi
$R close-windows 10 >/dev/null
# "Compare…" next to the world clock compares times across cities.
result=$(press_menu Tools "Compare…")
sleep 1
shown=$($R toolbox-tool 10)
if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"toolbox"* ]] && [ "$shown" = "tool=Time zones" ]; then pass "menu \"Compare…\" opens the time zone comparison"; else fail "menu \"Compare…\"" "$result $shown $(windows_now)"; fi
$R close-windows 10 >/dev/null

echo "==> menu panel buttons: Recent and Space"
result=$(press_menu Recent "All captures")
sleep 1
if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"history"* ]]; then pass "menu \"All captures\" opens the history"; else fail "menu \"All captures\"" "$result $(windows_now)"; fi
$R close-windows 10 >/dev/null
# The newest capture row opens its editor. The rows are read with the panel open on Recent.
$R close-panel 10 >/dev/null
$R press-status-item 10 >/dev/null
$R press:menubar:Recent 10 >/dev/null
sleep 0.5
newest=$($R controls:menubar 30 | sed 's/ ;; /\n/g' | grep -E "(ago|just now)$" | head -1 | cut -d'|' -f2)
result=$(press_menu Recent "$newest")
sleep 1
if [ -n "$newest" ] && [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"screenshot:"* || "$(windows_now)" == *"video:"* ]]; then pass "a recent capture opens in its editor ($newest)"; else fail "a recent capture opens" "$newest $result $(windows_now)"; fi
$R close-windows 10 >/dev/null
for row in "Open|history" "All categories|space" "What takes space…|space"; do
    label="${row%%|*}"
    window="${row##*|}"
    result=$(press_menu Space "$label")
    sleep 1
    if [ "$result" = "pressed" ] && [[ "$(windows_now)" == *"$window"* ]]; then pass "Space tab \"$label\" opens the $window window"; else fail "Space tab \"$label\"" "$result $(windows_now)"; fi
    $R close-windows 10 >/dev/null
done
# "Clean" on a category asks first; on a made-up home, and Cancel, so nothing real goes.
fake_home=$($R space-fake-home:on 60)
result=$(press_menu Space "Clean App caches")
sleep 0.5
asked=$($R controls:menubar 30 | sed 's/ ;; /\n/g' | grep -cE "^AXButton\|Delete ")
press_in menubar Cancel >/dev/null
sleep 0.5
if [ "$result" = "pressed" ] && [ "$asked" -ge 1 ] && [ -f "$fake_home/Library/Caches/com.example.app/blob.bin" ]; then pass "Space tab \"Clean\" asks first and \"Cancel\" keeps the files"; else fail "Space tab Clean" "$result asked=$asked"; fi
$R space-fake-home:off 60 >/dev/null
$R close-panel 10 >/dev/null

echo "==> history window buttons"
# Two screenshots of our own to select, compare and delete; the person's captures are only read.
$R screenshot-full 40 >/dev/null
sleep 1
$R screenshot-full 40 >/dev/null
sleep 1
$R close-windows 10 >/dev/null
read -r own_id _ <<< "$($R latest-capture 10)"
cards_now() { $R controls:history 30 | sed 's/ ;; /\n/g' | grep -E "^AXButton\|(Screenshot|Clip): " | cut -d'|' -f2-; }
press_menu Recent "All captures" >/dev/null
sleep 1
all_cards=$(cards_now | wc -l | tr -d ' ')
if [ "$all_cards" -ge 2 ]; then pass "history lists every capture as a card ($all_cards)"; else fail "history cards" "$all_cards"; fi

# Filters: only screenshots, only clips, all again.
press_in history Screenshots >/dev/null
sleep 0.5
if [ "$(cards_now | grep -c '^Clip: ')" = "0" ] && [ "$(cards_now | grep -c '^Screenshot: ')" -ge 2 ]; then pass "history filter \"Screenshots\" shows only screenshots"; else fail "history filter Screenshots" "$(cards_now | head -3)"; fi
press_in history Videos >/dev/null
sleep 0.5
if [ "$(cards_now | grep -c '^Screenshot: ')" = "0" ]; then pass "history filter \"Videos\" shows only clips"; else fail "history filter Videos" "$(cards_now | head -3)"; fi
press_in history All >/dev/null
sleep 0.5
if [ "$(cards_now | wc -l | tr -d ' ')" = "$all_cards" ]; then pass "history filter \"All\" shows everything again"; else fail "history filter All" "$(cards_now | wc -l)"; fi

# An app in the sidebar shows only its captures; "All" shows everything again.
first_app=$($R controls:history 30 | sed 's/ ;; /\n/g' | grep -E "^AXButton\|App: " | head -1 | sed 's/^AXButton|App: //')
press_in history "App: $first_app" >/dev/null
sleep 0.5
others=$(cards_now | grep -cv ": $first_app, ")
shown_app=$(cards_now | wc -l | tr -d ' ')
press_in history All >/dev/null
sleep 0.5
if [ -n "$first_app" ] && [ "$shown_app" -ge 1 ] && [ "$others" = "0" ] && [ "$(cards_now | wc -l | tr -d ' ')" = "$all_cards" ]; then pass "history sidebar app \"$first_app\" shows only its captures"; else fail "history sidebar app" "$first_app: $shown_app shown, $others of other apps"; fi

# Search: nothing matches a made-up word, clearing it brings the cards back.
$R "set-value:history:Search by app, URL…=zz-no-such-capture" 10 >/dev/null
sleep 0.5
searched=$(cards_now | wc -l | tr -d ' ')
$R "set-value:history:Search by app, URL…=" 10 >/dev/null
sleep 0.5
if [ "$searched" = "0" ] && [ "$(cards_now | wc -l | tr -d ' ')" = "$all_cards" ]; then pass "history search hides what does not match and clearing it shows all"; else fail "history search" "$searched then $(cards_now | wc -l)"; fi

# A card opens its editor.
first_card=$(cards_now | head -1)
press_in history "$first_card" >/dev/null
sleep 1.5
if [[ "$(windows_now)" == *"screenshot:"* || "$(windows_now)" == *"video:"* ]]; then pass "history card opens the capture in its editor"; else fail "history card opens" "$first_card $(windows_now)"; fi
$R close-windows 10 >/dev/null

# Select two screenshots: Step guide and Compare open their windows, Done leaves selecting.
open_history_selecting() {
    $R close-windows 10 >/dev/null
    press_menu Recent "All captures" >/dev/null
    sleep 1
    press_in history Screenshots >/dev/null
    press_in history Select >/dev/null
    sleep 0.5
    press_in history "$(cards_now | sed -n 1p)" >/dev/null
    press_in history "$(cards_now | sed -n 2p)" >/dev/null
    sleep 0.5
}
open_history_selecting
press_in history "Step guide" >/dev/null
sleep 1.5
if [[ "$(windows_now)" == *"step-guide"* ]]; then pass "history \"Select\" two screenshots, \"Step guide\" opens the guide"; else fail "history Step guide" "$(windows_now)"; fi
open_history_selecting
press_in history Compare >/dev/null
sleep 1.5
if [[ "$(windows_now)" == *"compare"* ]]; then pass "history \"Compare\" opens the comparison of the two picked"; else fail "history Compare" "$(windows_now)"; fi
open_history_selecting
press_in history Done >/dev/null
sleep 0.5
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
sleep 1
card_menu() { $R "choose:history:More actions => $1" 10; }
card_menu "Open" >/dev/null
sleep 1
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
sleep 1
before=$(capture_count)
card_menu "Delete…" >/dev/null
sleep 0.5
asked=$(capture_count)
press_in history Delete >/dev/null
sleep 1
after=$(capture_count)
if [ "$asked" = "$before" ] && [ "$after" = "$((before - 1))" ] && [[ "$($R latest-capture 10)" != "$own_id"* ]]; then pass "history menu \"Delete…\" asks, then deletes only that capture"; else fail "history Delete" "$before → $asked → $after"; fi
$R close-windows 10 >/dev/null

echo "==> disk space buttons"
# Everything here works on a made-up home and Applications folder; Move to Trash is recorded, not done.
fake_home=$($R space-fake-home:on 60)
space_controls() { $R controls:space 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2-; }
space_state() { $R space-state 10; }
$R open-space:Clean\ up 10 >/dev/null
sleep 1
$R system-actions:start 10 >/dev/null

# Clean: asks first, Cancel keeps the files, Delete removes them.
press_in space "Clean App caches" >/dev/null
sleep 0.5
delete_label=$(space_controls | grep -E "^Delete " | head -1)
press_in space Cancel >/dev/null
sleep 0.5
if [ -n "$delete_label" ] && [ -f "$fake_home/Library/Caches/com.example.app/blob.bin" ] && ! space_controls | grep -q "^Delete "; then pass "Space \"Clean\" asks first and \"Cancel\" keeps the files"; else fail "Space Clean, Cancel" "$delete_label"; fi
press_in space "Clean App caches" >/dev/null
sleep 0.5
press_in space "$(space_controls | grep -E "^Delete " | head -1)" >/dev/null
sleep 2
if [ ! -f "$fake_home/Library/Caches/com.example.app/blob.bin" ] && [[ "$(space_state)" == *"appCaches=Zero KB"* ]]; then pass "Space \"Delete …\" cleans the category"; else fail "Space Delete" "$(space_state)"; fi

# Measure again picks up a new cache file.
mkdir -p "$fake_home/Library/Caches/com.example.other"
dd if=/dev/zero of="$fake_home/Library/Caches/com.example.other/new.bin" bs=1m count=2 2>/dev/null
press_in space "Measure again" >/dev/null
sleep 2
if [[ "$(space_state)" == *"appCaches=2"* ]]; then pass "Space \"Measure again\" measures fresh sizes"; else fail "Space Measure again" "$(space_state)"; fi

# Our captures open in the history.
press_in space Open >/dev/null
sleep 1
if [[ "$(windows_now)" == *"history"* ]]; then pass "Space \"Open\" on the captures row opens the history"; else fail "Space Open" "$(windows_now)"; fi

# Folders: the app data switch flips and comes back, Scan and Stop.
press_in space Folders >/dev/null
sleep 0.5
before=$(space_state)
press_in space "Include other apps' private data (Docker, Slack, Telegram…). macOS asks once." >/dev/null
flipped=$(space_state)
press_in space "Include other apps' private data (Docker, Slack, Telegram…). macOS asks once." >/dev/null
app_data_before=$(echo "$before" | tr ' ' '\n' | grep '^appData=')
app_data_flipped=$(echo "$flipped" | tr ' ' '\n' | grep '^appData=')
if [ -n "$app_data_before" ] && [ "$app_data_before" != "$app_data_flipped" ] && [[ "$(space_state)" == *"$app_data_before"* ]]; then pass "Space switch \"Include other apps' private data\" turns on and off"; else fail "Space app data switch" "$before / $flipped"; fi
press_in space "Scan home folder and Applications" >/dev/null
sleep 0.3
press_in space Stop >/dev/null
sleep 1
if [[ "$(space_state)" == *"scan=idle"* ]]; then pass "Space \"Stop\" stops the scan"; else fail "Space Stop" "$(space_state)"; fi
press_in space "Scan home folder and Applications" >/dev/null
for _ in $(seq 1 180); do
    [[ "$(space_state)" == *"scan=done"* ]] && break
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
sleep 0.5
press_in space "Show bugbear-test-big.bin in Finder" >/dev/null
if [[ "$($R system-actions:read 10)" == *"reveal $fake_home/Downloads/bugbear-test-big.bin"* ]]; then pass "Space \"Show\" shows the file in Finder"; else fail "Space Show file" "$($R system-actions:read 10)"; fi
press_in space "Move bugbear-test-big.bin to Trash" >/dev/null
press_in space "Keep bugbear-test-big.bin" >/dev/null
if space_controls | grep -q "^Move bugbear-test-big.bin to Trash$" && [[ "$($R system-actions:read 10)" != *"trash "* ]]; then pass "Space \"Move to Trash\" asks first and \"Cancel\" keeps the file"; else fail "Space Move to Trash, Cancel"; fi
press_in space "Move bugbear-test-big.bin to Trash" >/dev/null
press_in space "Move bugbear-test-big.bin to the Trash now" >/dev/null
if [[ "$($R system-actions:read 10)" == *"trash $fake_home/Downloads/bugbear-test-big.bin"* ]] && ! space_controls | grep -q "bugbear-test-big.bin"; then pass "Space \"Move\" moves the file to the Trash and drops its row"; else fail "Space Move" "$($R system-actions:read 10)"; fi

# Scan again from the folder list starts a fresh scan.
press_in space Folders >/dev/null
press_in space "Scan again" >/dev/null
sleep 0.3
again=$(space_state)
for _ in $(seq 1 180); do
    [[ "$(space_state)" == *"scan=done"* ]] && break
    sleep 1
done
if [[ "$again" == *"scan=running"* && "$(space_state)" == *"scan=done"* ]]; then pass "Space \"Scan again\" scans again"; else fail "Space Scan again" "$again"; fi
$R system-actions:stop 10 >/dev/null
$R close-windows 10 >/dev/null
$R space-fake-home:off 60 >/dev/null

echo "==> toolbox buttons"
# Every tool gets an input typed into its fields; results are read from its Output and from what
# its Copy buttons put on the clipboard. Saved time zones are put back at the end.
tb_open() { $R "toolbox-open:$1" 10 >/dev/null; sleep 0.5; }
tb_set() { $R "set-value:toolbox:$1=$2" 10 >/dev/null; sleep 0.3; }
tb_value() { local shown; shown=$($R "control-value:toolbox:$1" 10); echo "${shown#value=}"; }
tb_press() { press_in toolbox "$1" >/dev/null; sleep 0.3; }
tb_controls() { $R controls:toolbox 30 | sed 's/ ;; /\n/g'; }
# tb_copies <label>: presses a copy button and prints what it put on the clipboard (nothing when it put nothing).
tb_copies() {
    printf 'bugbear-sentinel' | pbcopy
    tb_press "$1"
    local text
    text=$(pbpaste)
    if [ "$text" != "bugbear-sentinel" ]; then printf '%s' "$text"; fi
}
toolbox_listing="$WORK/toolbox-controls.txt"
: > "$toolbox_listing"
# tb_every_copy <tool>: every Copy button of the open tool puts something on the clipboard; the
# tool's controls go to the coverage listing.
tb_every_copy() {
    local label copied empty=""
    tb_controls >> "$toolbox_listing"
    while IFS= read -r label; do
        copied=$(tb_copies "$label")
        if [ -z "$copied" ]; then empty="$empty \"$label\""; fi
    done < <(tb_controls | cut -d'|' -f2- | grep -E "^Copy" | grep -vxF "Copy as…")
    if [ -z "$empty" ]; then pass "toolbox $1: every Copy button copies"; else fail "toolbox $1 Copy buttons" "$empty"; fi
}
saved_zones=$($R time-zones 10)

# Sidebar rows open their tool; search narrows the list; Paste & detect picks the tool.
tb_open JSON
TOOLS=("JSON" "XML" "YAML" "HTML" "SQL" "GraphQL" "JWT" "Base64" "URL encode" "HTML entities" "Time & dates" "Time zones" "JSON ↔ YAML ↔ XML ↔ CSV" "Numbers, colors, case" "UUID · hash" "Test data" "QR code" "Regex" "JSON diff" "JSONPath" "HTTP message" "Cron" "String length" "Color & contrast")
wrong=""
for tool in "${TOOLS[@]}"; do
    tb_press "$tool"
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
    printf 'bugbear-sentinel' | pbcopy
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
printf 'bugbear-sentinel' | pbcopy
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
tb_set Input "https://bugbear.test/qr"
tb_press "Copy image"
image_types=$($R pasteboard-types 10)
tb_set Input "x"
tb_press "Read from clipboard image"
sleep 1
read_back=$(tb_value Input)
$R system-actions:start 10 >/dev/null
rm -f "$WORK/qr.png"
$R "system-actions:files:$WORK/qr.png" 10 >/dev/null
tb_press "Save PNG…"
sleep 0.5
$R system-actions:stop 10 >/dev/null
if [[ "$image_types" == *png* || "$image_types" == *tiff* ]] && [ "$read_back" = "https://bugbear.test/qr" ]; then pass "toolbox QR \"Copy image\" and \"Read from clipboard image\" round trip"; else fail "toolbox QR copy and read" "$image_types / $read_back"; fi
if file "$WORK/qr.png" 2>/dev/null | grep -q PNG; then pass "toolbox QR \"Save PNG…\" writes the code"; else fail "toolbox QR save"; fi
tb_press "Read from screen…"
sleep 1
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
for example in '$..id' '$.items[*]' '$.items[0]' '$..*'; do
    tb_press "$example"
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
for example in "*/5 * * * *" "0 9 * * 1-5" "30 2 * * 0" "0 0 1 * *" "@hourly" "0 */6 * * *"; do
    tb_press "$example"
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
sleep 0.5
picking=$(tools_now)
$R post-key:53:none 10 >/dev/null
sleep 0.5
tb_press "Pick the background color"
sleep 0.5
picking_back=$(tools_now)
$R post-key:53:none 10 >/dev/null
sleep 0.5
if [[ "$picking" == *"picking=true"* && "$picking_back" == *"picking=true"* && "$(tools_now)" == *"picking=false"* ]]; then pass "toolbox contrast eyedroppers open the color loupe, Esc closes it"; else fail "toolbox contrast eyedroppers" "$picking"; fi
tb_controls >> "$toolbox_listing"
$R close-windows 10 >/dev/null

echo "==> welcome guide buttons"
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
sleep 1.5
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
sleep 0.5
if [[ "$(windows_now)" != *"onboarding"* ]] && [ "$(setting_value onboardingCompleted)" = 1 ]; then pass "guide \"Start using $APP_NAME\" finishes the guide"; else fail "guide Start using Bugbear" "$(windows_now)"; fi
$R open-onboarding 10 >/dev/null
press_in onboarding Skip >/dev/null
sleep 0.5
if [[ "$(windows_now)" != *"onboarding"* ]]; then pass "guide \"Skip\" closes the guide"; else fail "guide Skip"; fi
$R system-actions:stop 10 >/dev/null
if [ -n "$saved_guide_page" ]; then defaults write "$BUNDLE_ID" onboardingPage -int "$saved_guide_page"; fi
echo "$onboarding_controls" > "$WORK/onboarding-controls.txt"

echo "==> feedback window buttons"
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
sleep 1
opened=$($R system-actions:read 10)
if [[ "$opened" == *"open https://github.com/"*"Buttons"*"test"*"title"* ]]; then pass "feedback title and details are typed, \"Open on GitHub\" opens the filled form"; else fail "feedback Open on GitHub" "$opened"; fi
$R open-feedback:problem:keep 10 >/dev/null
press_in feedback Cancel >/dev/null
sleep 0.5
if [[ "$(windows_now)" != *"feedback"* ]]; then pass "feedback \"Cancel\" closes the window"; else fail "feedback Cancel"; fi
$R system-actions:stop 10 >/dev/null

echo "==> update badge buttons"
$R system-actions:start 10 >/dev/null
$R update-fake:available 10 >/dev/null
$R close-panel 10 >/dev/null
$R press-status-item 10 >/dev/null
press_in menubar "Update to 9.9.9" >/dev/null
sleep 0.5
popover_controls=$($R controls:popover 30)
echo "$popover_controls" | sed 's/ ;; /\n/g' | sed "s#^#update|#" > "$WORK/update-controls.txt"
press_in popover "#42 Fake change for tests" >/dev/null
link=$($R system-actions:read 10)
press_in popover "Another fake change" >/dev/null
commit_link=$($R system-actions:read 10)
press_in popover Later >/dev/null
sleep 0.5
later=$($R controls:popover 30)
press_in menubar "Update to 9.9.9" >/dev/null
sleep 0.5
press_in popover "Update now" >/dev/null
sleep 0.5
if [[ "$popover_controls" == *"|Update now"* && "$link" == *"open https://github.com/"*"/pull/42"* && "$later" != *"|Later"* ]]; then pass "update badge opens the changes, a change links to its pull request, \"Later\" closes"; else fail "update badge details" "$link / $later"; fi
if [[ "$commit_link" == *"open https://github.com/"*"/commit/def5678"* ]]; then pass "update badge: a change without a pull request links to its commit"; else fail "update badge commit link" "$commit_link"; fi
if [[ "$($R system-actions:read 10)" == *"update"* ]]; then pass "update badge \"Update now\" starts the update"; else fail "update now" "$($R system-actions:read 10)"; fi
$R update-fake:failed 10 >/dev/null
press_in menubar "The update failed, show why" >/dev/null
sleep 0.5
$R controls:popover 30 | sed 's/ ;; /\n/g' | sed "s#^#update|#" >> "$WORK/update-controls.txt"
press_in popover "Show log" >/dev/null
press_in popover "Check again" >/dev/null
sleep 0.5
actions=$($R system-actions:read 10)
if [[ "$actions" == *"update.log"* && "$actions" == *"check for updates"* ]]; then pass "failed update \"Show log\" and \"Check again\""; else fail "failed update buttons" "$actions"; fi
$R update-fake:idle 10 >/dev/null
$R close-panel 10 >/dev/null
open_settings
$R "settings-page:Updates and feedback" 10 >/dev/null
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

echo "==> what's new buttons"
$R whats-new 10 >/dev/null
sleep 1
$R controls:whats-new 30 | sed 's/ ;; /\n/g' | sed "s#^#whats-new|#" > "$WORK/whats-new-controls.txt"
press_in whats-new "Got it" >/dev/null
sleep 0.5
if [[ "$(windows_now)" != *"whats-new"* ]]; then pass "What's New \"Got it\" closes it"; else fail "What's New Got it" "$(windows_now)"; fi

echo "==> step guide and comparison buttons"
$R screenshot-full 40 >/dev/null
$R screenshot-full 40 >/dev/null
$R close-windows 10 >/dev/null
$R "guide-latest:2:$WORK" 30 >/dev/null
sleep 1
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
sleep 1
$R system-actions:stop 10 >/dev/null
press_in step-guide "Remove step 2" >/dev/null
if [ "$moved_up" = "value=second" ] && [ "$moved_down" = "value=first" ]; then pass "step guide \"Move step up\" and \"Move step down\" reorder the captions"; else fail "step guide move" "$moved_up $moved_down"; fi
if [[ "$guide_image" == *png* || "$guide_image" == *tiff* ]] && file "$WORK/guide-test.pdf" | grep -q PDF && file "$WORK/guide-test.png" | grep -q PNG; then pass "step guide \"Copy image\", \"Save PDF…\" and \"Save PNG…\" with the typed title"; else fail "step guide copy and save" "$guide_image"; fi
if [ "$($R control-value:step-guide:"Caption of step 2" 10)" = "not found" ]; then pass "step guide \"Remove step\" takes it out"; else fail "step guide remove"; fi
$R close-windows 10 >/dev/null
$R compare-latest 30 >/dev/null
sleep 1
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
    sleep 1
    playing=$($R controls:compare 30)
    press_in compare "Pause both" >/dev/null
    paused=$($R control-value:compare:Position 10)
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

echo "==> design overlay and recording bar buttons"
$R overlay-test:2 10 >/dev/null
sleep 0.5
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
sleep 0.5
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
sleep 0.5
if [[ "$picked" == *"liveTool=rectangle"* && "$picked" == *"liveColor=yellow"* && "$picked" == *"fade=true"* && "$fade_flipped" == *"fade=false"* && "$(tools_now)" == *"fade=true"* ]]; then pass "drawing bar tool, color and fade buttons"; else fail "drawing bar tool, color, fade" "$picked / $fade_flipped"; fi
if [ "$undo" = pressed ] && [ "$clear" = pressed ] && [[ "$not_drawing" == *"drawing=false"* && "$(windows_now)" != *"recording-bar"* ]]; then pass "drawing bar undo, clear, stop drawing and close"; else fail "drawing bar" "$undo $clear $not_drawing $(windows_now)"; fi
live_field() { echo "$1" | tr ' ' '\n' | grep "^$2=" | cut -d= -f2-; }
# Text on the screen: with Text, a click puts a field there; Return keeps the text as a mark,
# Esc drops it. Typed with real keys, so any keyboard layout works.
$R "activate-app:$BROWSER" 10 >/dev/null
sleep 0.5
$R draw-toggle 10 >/dev/null
sleep 0.5
press_in recording-bar "Text" >/dev/null
press_in recording-bar "coral" >/dev/null
# Marks stay for this check: a mark that fades after 3.8 s must not make it flaky.
press_in recording-bar "Marks fade after 3 s (click to keep)" >/dev/null
live=$($R live-state 10)
lx=$(live_field "$live" x); ly=$(live_field "$live" y); lw=$(live_field "$live" w); lh=$(live_field "$live" h)
text_x=$((lx + lw / 3))
text_y=$((ly + lh / 3))
$R "post-click:$text_x,$text_y" 10 >/dev/null
sleep 0.5
typing=$($R live-state 10)
$R post-text:Login 10 >/dev/null
$R post-key:36:none 10 >/dev/null
sleep 0.5
typed=$($R live-state 10)
text_pixels=$(live_field "$($R "screen-color:$text_x,$text_y,160,50:FF6B4A" 20)" coral)
if [ "$(live_field "$typing" typing)" = "true" ] && [ "$(live_field "$typed" lastKind)" = "text" ] && [ "$(live_field "$typed" lastText)" = "Login" ] && [ "$(live_field "$typed" typing)" = "false" ]; then pass "drawing bar \"Text\": a click and typing put text on the screen"; else fail "drawing text on the screen" "$typing / $typed"; fi
if [ "${text_pixels:-0}" -gt 150 ] 2>/dev/null; then pass "the text shows on the screen"; else fail "the text shows on the screen" "$text_pixels"; fi
marks_before=$(live_field "$typed" marks)
$R "post-click:$((text_x + 200)),$((text_y + 150))" 10 >/dev/null
sleep 0.5
$R post-text:Dropped 10 >/dev/null
$R post-key:53:none 10 >/dev/null
sleep 0.5
cancelled=$($R live-state 10)
if [ "$(live_field "$cancelled" typing)" = "false" ] && [ "$(live_field "$cancelled" drawing)" = "true" ] && [ "$(live_field "$cancelled" lastText)" = "Login" ] && [ "$(live_field "$cancelled" marks)" -le "$marks_before" ]; then pass "Esc drops the text being typed and keeps drawing"; else fail "Esc while typing text" "$cancelled"; fi
press_in recording-bar "Marks stay (click to fade)" >/dev/null
$R draw-hide 10 >/dev/null
before=$(capture_count)
press_menu Record "Start recording" >/dev/null
sleep 2
bar=$($R controls:recording-bar 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2-)
$R controls:recording-bar 30 | sed 's/ ;; /\n/g' | sed "s#^#recording-bar|#" >> "$WORK/bar-controls.txt"
press_in recording-bar "$(echo "$bar" | grep -E "^Pause the recording" | head -1)" >/dev/null
paused=$(tools_now)
press_in recording-bar "$($R controls:recording-bar 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -E "^Resume the recording" | head -1)" >/dev/null
resumed=$(tools_now)
press_in recording-bar "Stop and throw the recording away without saving" >/dev/null
sleep 2
if [[ "$paused" == *"paused=true"* && "$resumed" == *"paused=false"* && "$(tools_now)" == *"recording=false"* && "$(capture_count)" = "$before" ]]; then pass "recording bar pause, resume and \"throw away\" saves nothing"; else fail "recording bar" "$paused / $resumed / $(capture_count)"; fi
press_menu Record "Start recording" >/dev/null
sleep 2
press_in recording-bar Stop >/dev/null
sleep 4
if [ "$(capture_count)" = "$((before + 1))" ]; then pass "recording bar \"Stop\" saves the recording"; else fail "recording bar Stop"; fi
$R close-windows 10 >/dev/null

echo "==> every control has a check"
# The controls on screen now, against scripts/check/controls.txt: a new button without a check fails.
listing="$WORK/controls.txt"
: > "$listing"
$R close-panel 10 >/dev/null
$R press-status-item 10 >/dev/null
for tab in Capture Record Tools Recent Space; do
    $R "press:menubar:$tab" 10 >/dev/null
    sleep 0.5
    $R controls:menubar 30 | sed 's/ ;; /\n/g' | sed "s#^#menubar/$tab|#" >> "$listing"
done
$R close-panel 10 >/dev/null
press_menu Capture "Open settings: buffer, shortcuts, storage and more" >/dev/null
sleep 1
$R tall-window:settings 10 >/dev/null
# Settings shows one page at a time: list every page.
for page in "General" "Buffer and recording" "Bug reports" "Storage" "Shortcuts" "Updates and feedback"; do
    $R "settings-page:$page" 10 >/dev/null
    $R controls:settings 30 | sed 's/ ;; /\n/g' | sed "s#^#settings|#" >> "$listing"
done
$R close-windows 10 >/dev/null
press_menu Recent "All captures" >/dev/null
sleep 1
$R controls:history 30 | sed 's/ ;; /\n/g' | sed "s#^#history|#" >> "$listing"
$R "menu-items:history:More actions" 10 | sed 's/ ;; /\n/g' | sed "s#^#history-menu|AXMenuItem|#" >> "$listing"
$R close-windows 10 >/dev/null
# Windows that need a state to show their controls were listed by their own sections.
for listed in onboarding feedback update whats-new guide compare overlay bar picker; do
    if [ -s "$WORK/$listed-controls.txt" ]; then grep -v '^[^|]*|$' "$WORK/$listed-controls.txt" | sort -u >> "$listing"; else fail "no controls listed for $listed: run its section first"; fi
done
# The toolbox controls were listed tool by tool in "toolbox buttons".
if [ -s "$WORK/toolbox-controls.txt" ]; then sed "s#^#toolbox|#" "$WORK/toolbox-controls.txt" | sort -u >> "$listing"; else fail "toolbox controls listing is empty: run the toolbox section first"; fi
# Disk Space on a made-up home: every section, with its questions open.
$R space-fake-home:on 60 >/dev/null
list_space() { $R controls:space 30 | sed 's/ ;; /\n/g' | sed "s#^#space|#" >> "$listing"; }
$R open-space:Clean\ up 10 >/dev/null
sleep 1
$R "press:space:Clean App caches" 10 >/dev/null
list_space
$R "press:space:Folders" 10 >/dev/null
list_space
$R space-scan 60 >/dev/null
$R "press:space:$($R controls:space 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -E "^Folder Home, " | head -1)" 10 >/dev/null
list_space
$R "press:space:Largest files" 10 >/dev/null
$R "press:space:Move bugbear-test-big.bin to Trash" 10 >/dev/null
list_space
$R close-windows 10 >/dev/null
$R space-fake-home:off 60 >/dev/null
$R screenshot-full 40 >/dev/null
sleep 2
$R controls:screenshot: 30 | sed 's/ ;; /\n/g' | sed "s#^#screenshot:|#" >> "$listing"
$R close-windows 10 >/dev/null
$R save:5 60 >/dev/null
sleep 3
$R controls:video: 30 | sed 's/ ;; /\n/g' | sed "s#^#video:|#" >> "$listing"
$R close-windows 10 >/dev/null
# A window that did not open lists nothing, and nothing to list would pass without looking.
for area in menubar/Capture menubar/Record menubar/Tools menubar/Recent menubar/Space settings history space "screenshot:" "video:"; do
    if [ "$(grep -c "^$area|AX" "$listing")" -lt 3 ]; then fail "no controls listed for $area" "the window did not open in time"; fi
done
if coverage=$(python3 -I scripts/check/control-coverage.py "$listing"); then pass "every control of every window has a check ($(wc -l < "$listing" | tr -d ' ') controls)"; else fail "controls without a check" "$coverage"; fi

echo "==> settings buttons"
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
    press_in settings "$label" >/dev/null
    sleep 0.5
    second=$(setting_value "$key")
    press_in settings "$label" >/dev/null
    sleep 0.5
    third=$(setting_value "$key")
    if [ "$first" != "$second" ] && [ "$first" = "$third" ]; then pass "settings switch \"$label\" turns $key on and off"; else fail "settings switch \"$label\"" "$first → $second → $third"; fi
done

# Buttons that hand something to macOS say what they would open instead of opening it.
$R system-actions:start 10 >/dev/null
for row in "Choose…|choose folder" "Show in Finder|/Captures" "Open at login|login "; do
    label="${row%%|*}"
    expected="${row##*|}"
    press_in settings "$label" >/dev/null
    sleep 0.5
    recorded=$($R system-actions:read 10)
    if [[ "$recorded" == *"$expected"* ]]; then pass "settings button \"$label\" asks macOS for the right thing"; else fail "settings button \"$label\"" "$recorded"; fi
done
press_in settings "Open at login" >/dev/null
# Permissions page: each permission has Allow… (not given yet) or Open… (given), and each asks
# macOS or opens its own part of System Settings.
$R settings-page:Permissions 10 >/dev/null
sleep 0.5
permission_controls=$($R controls:settings 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2-)
pressed=0
wrong=""
for row in "Screen & System Audio Recording|ScreenCapture|Screen Recording" "Accessibility|Privacy_Accessibility|Accessibility" "Microphone|Privacy_Microphone|Microphone" "Camera|Privacy_Camera|Camera" "Browsers (Automation)|Privacy_Automation|Automation"; do
    title="${row%%|*}"
    rest="${row#*|}"
    pane="${rest%%|*}"
    asked="${rest##*|}"
    before_count=$($R system-actions:read 10 | sed 's/ ;; /\n/g' | grep -c .)
    if echo "$permission_controls" | grep -qx "Open $title in System Settings"; then
        press_in settings "Open $title in System Settings" >/dev/null
        expected="$pane"
    else
        press_in settings "Allow $title" >/dev/null
        expected="$asked"
    fi
    sleep 0.5
    recorded=$($R system-actions:read 10 | sed 's/ ;; /\n/g' | tail -n +$((before_count + 1)))
    if [[ "$recorded" == *"$expected"* ]]; then pressed=$((pressed + 1)); else wrong="$wrong $title:$recorded"; fi
done
if [ "$pressed" = "5" ]; then pass "settings permissions page asks macOS or opens System Settings for each permission"; else fail "settings permissions page" "$wrong"; fi
$R buffer-needs-permission:on 10 >/dev/null
sleep 1.5
relaunch_result=$(press_in settings Relaunch)
$R buffer-needs-permission:off 10 >/dev/null
if [ "$relaunch_result" = "pressed" ] && [[ "$($R system-actions:read 10)" == *"relaunch"* ]]; then pass "settings \"Relaunch\" restarts the app after Screen Recording is allowed"; else fail "settings Relaunch" "$relaunch_result"; fi
$R settings-page:General 10 >/dev/null
$R system-actions:stop 10 >/dev/null

started_before=$(grep -c "buffer\[.*\] started" "$LOG")
press_in settings "Show the mouse pointer" >/dev/null
sleep 0.5
press_in settings "Restart buffer" >/dev/null
sleep 3
press_in settings "Show the mouse pointer" >/dev/null
press_in settings "Restart buffer" >/dev/null
sleep 3
if [ "$(grep -c "buffer\[.*\] started" "$LOG")" -gt "$started_before" ]; then pass "settings \"Restart buffer\" restarts the buffer with the new settings"; else fail "settings \"Restart buffer\""; fi

for row in "Report a problem…|feedback" "Suggest a feature…|feedback" "Show the welcome guide|onboarding" "Show what's new|whats-new"; do
    label="${row%%|*}"
    window="${row##*|}"
    open_settings
    press_in settings "$label" >/dev/null
    sleep 1
    if [[ "$(windows_now)" == *"$window"* ]]; then pass "settings \"$label\" opens the $window window"; else fail "settings \"$label\"" "$(windows_now)"; fi
done

open_settings
fields_before=$($R fields-count 10)
press_in settings "New field" >/dev/null
sleep 0.5
fields_added=$($R fields-count 10)
press_in settings "Remove field#last" >/dev/null
sleep 0.5
fields_after=$($R fields-count 10)
if [ "$fields_added" != "$fields_before" ] && [ "$fields_after" = "$fields_before" ]; then pass "settings \"New field\" adds a report field and \"Remove field\" removes it"; else fail "settings add and remove field" "$fields_before / $fields_added / $fields_after"; fi

# A suggested name adds a field with that name.
open_settings
$R "settings-page:Bug reports" 10 >/dev/null
fields_before=$($R fields-count 10)
suggestion=$($R controls:settings 30 | sed 's/ ;; /\n/g' | grep -E "^AXButton\|(Stand|Build|Test account|Browser profile|Feature flag|Severity)$" | head -1 | cut -d'|' -f2)
press_in settings "$suggestion" >/dev/null
sleep 0.5
fields_added=$($R fields-count 10)
newest_field=$($R fields-read 10 | tr ',' '\n' | tail -1)
press_in settings "Remove field#last" >/dev/null
sleep 0.5
if [ -n "$suggestion" ] && [ "$newest_field" = "$suggestion=" ] && [ "$fields_added" != "$fields_before" ] && [ "$($R fields-count 10)" = "$fields_before" ]; then pass "settings suggestion \"$suggestion\" adds a field with that name"; else fail "settings field suggestion" "$suggestion $fields_before / $fields_added, newest $newest_field"; fi

# A changed shortcut and "Reset to defaults"; a shortcut button waits for keys, Esc cancels.
# Reset would also drop shortcuts the person set, so with their own shortcuts it is skipped.
if [ -n "$(defaults read "$BUNDLE_ID" customHotKeys 2>/dev/null | tr -d '{}() \n')" ]; then
    echo "SKIP  settings \"Reset to defaults\": the person has their own shortcuts"
else
    press_in settings "Save the last 30 s: ⌥⇧1" >/dev/null
    sleep 0.5
    $R post-key:53:none 10 >/dev/null
    $R hotkey-set:ruler:25:cmd,shift 10 >/dev/null
    open_settings
    press_in settings "Reset to defaults" >/dev/null
    sleep 0.5
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
sleep 2
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
    $R "choose:settings:$label => $other" 10 >/dev/null
    changed=$(setting_value "$key")
    $R "choose:settings:$label => $shown" 10 >/dev/null
    after=$(setting_value "$key")
    # Never leave a storage limit (or any choice) changed when choosing back did not work.
    if [ "$after" != "$before" ]; then $R "setting-write:$key=$before" 10 >/dev/null; fi
    if [ -n "$other" ] && [ "$changed" != "$before" ] && [ "$after" = "$before" ]; then pass "settings picker \"$label\" sets $key ($shown → $other → back)"; else fail "settings picker \"$label\"" "$shown/$other: $before → $changed → $after"; fi
done
$R cleanup-pause:off 10 >/dev/null
$R close-windows 10 >/dev/null

echo "==> settings pages and report fields"
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
# Fields Bugbear fills in: every one is listed, can be turned off and renamed, and a new
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
sleep 2
edit_result=$(press_in screenshot: Edit)
sleep 1
shown=$($R controls:settings 30)
if [ "$edit_result" = "pressed" ] && [[ "$shown" == *"|Include Device"* ]]; then pass "editor \"Edit\" next to Environment opens Settings on Bug reports"; else fail "editor Edit environment" "$edit_result"; fi
$R "setting-write:hiddenEnvironmentFields=Appearance" 10 >/dev/null
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

echo "==> screenshot editor buttons"
# Saves go to a test folder, not the person's Desktop/Bugbear.
saved_output=$(setting_value outputFolderPath)
out_dir="$WORK/editor-out"
rm -rf "$out_dir"
mkdir -p "$out_dir"
$R "setting-write:outputFolderPath=$out_dir" 10 >/dev/null
$R close-windows 10 >/dev/null
$R screenshot-full 40 >/dev/null
sleep 2
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
sleep 0.5
if [[ "$(windows_now)" == *"NSColorPanel"* ]]; then pass "editor \"Pick any color\" opens the color panel"; else fail "editor \"Pick any color\"" "$(windows_now)"; fi
$R close-color-panel 10 >/dev/null

# Insert a picture from a file, undo and redo it, combine with another screenshot.
shot=$(ls -t "$HOME/Library/Application Support/Bugbear/Captures"/*/original.png | head -1)
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
sleep 1
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
sleep 1
saved=$(ls "$out_dir" | head -1)
if [ -n "$saved" ] && $R system-actions:read 10 | grep -q "reveal $out_dir/"; then pass "editor \"Save to folder\" writes the picture to the chosen folder and shows it ($saved)"; else fail "editor save to folder" "$saved"; fi
printf '' | pbcopy
press_in screenshot: "Copy  ⌘C" >/dev/null
sleep 0.5
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
sleep 2
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

echo "==> video editor buttons"
saved_output=$(setting_value outputFolderPath)
out_dir="$WORK/video-out"
rm -rf "$out_dir"
mkdir -p "$out_dir"
$R "setting-write:outputFolderPath=$out_dir" 10 >/dev/null
video_state() { $R video-state 10; }
vfield() { echo "$1" | tr ' ' '\n' | grep "^$2=" | cut -d= -f2-; }
# A 10 s clip: right after the app starts the buffer holds less, so wait and save again.
for _ in 1 2 3; do
    $R close-windows 10 >/dev/null
    $R save:10 60 >/dev/null
    sleep 3
    clip_length=$(vfield "$(video_state)" duration)
    if awk "BEGIN { exit !(${clip_length:-0} >= 9.5) }"; then break; fi
    sleep 8
done
$R system-actions:start 10 >/dev/null

press_in video: "Play" >/dev/null
sleep 1
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
    sleep 0.5
    echo "clicked"
}
before_count=$(vfield "$(video_state)" overlays)
$R video-seek:2 10 >/dev/null
for row in "Text|text" "Arrow|arrow" "Box|rectangle" "Blur|blur"; do
    tool_label="${row%%|*}"
    tool_name="${row##*|}"
    click_control "$tool_label" >/dev/null
    picked=$(vfield "$(video_state)" tool)
    click_control "$tool_label" >/dev/null
    put_down=$(vfield "$(video_state)" tool)
    if [ "$picked" = "$tool_name" ] && [ "$put_down" = "select" ]; then pass "video a real click on \"$tool_label\" picks the tool and puts it down"; else fail "video real click on $tool_label" "$picked $put_down"; fi
done
click_control "Arrow" >/dev/null
$R "post-drag:$(at 0.3 0.3):$(at 0.5 0.5)" 10 >/dev/null
sleep 1.5
drawn=$(video_state)
shown=$($R video-frame-diff 20)
if [ "$(vfield "$shown" changed)" -gt 50 ] 2>/dev/null; then pass "video the arrow drawn shows on the preview frame"; else fail "video arrow not on the preview" "$shown"; fi
if [ "$(vfield "$drawn" overlays)" = "$((before_count + 1))" ] && [ "$(vfield "$drawn" lastLength)" = "3.0" ] && inside "$(vfield "$drawn" lastBox)" && [ "$(vfield "$drawn" tool)" = "select" ]; then pass "video an arrow drawn with the mouse shows for 3 s inside the frame"; else fail "video draw with the mouse" "$stage_line / $drawn"; fi
# With Select, a drag away from the selected mark leaves it where it is.
box_before=$(vfield "$drawn" lastBox)
$R "post-drag:$(at 0.85 0.85):$(at 0.95 0.9)" 10 >/dev/null
sleep 0.8
box_after=$(vfield "$(video_state)" lastBox)
if [ "$box_after" = "$box_before" ]; then pass "video a drag away from the selected mark does not move it"; else fail "video drag away moved the mark" "$box_before → $box_after"; fi
# Dragged on the mark far past the edge, it moves and stops at the edge of the frame.
$R "post-drag:$(at 0.4 0.4):$(at 1.4 0.45)" 10 >/dev/null
sleep 0.8
moved=$(vfield "$(video_state)" lastBox)
if [ "$moved" != "$box_before" ] && inside "$moved"; then pass "video a mark dragged past the edge stays inside the frame"; else fail "video drag past the edge" "$box_before → $moved"; fi
# Drawn at the last frame with the mouse, it still shows for 3 s.
$R video-seek:end 10 >/dev/null
press_in video: "Box" >/dev/null
$R "post-drag:$(at 0.2 0.6):$(at 0.4 0.8)" 10 >/dev/null
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
sleep 1
picking=$(video_state)
if [ "$(vfield "$picking" tool)" = "crop" ] && [ "$(vfield "$picking" render)" = "$(vfield "$picking" source)" ]; then pass "video \"Crop\" shows the whole frame to pick from"; else fail "video crop tool" "$picking"; fi
$R "post-drag:$(at 0.25 0.25):$(at 0.75 0.75)" 10 >/dev/null
sleep 0.8
drawn_crop=$(vfield "$(video_state)" crop)
$R "post-drag:$(at 0.75 0.75):$(at 0.9 0.75)" 10 >/dev/null
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
waited=0
while [ -z "$(ls "$crop_out" 2>/dev/null)" ] && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
sleep 1
crop_file="$crop_out/$(ls "$crop_out" | head -1)"
crop_dimensions=$(avmediainfo "$crop_file" 2>/dev/null | grep -m1 "Dimensions:" | sed -E 's/.*Dimensions: ([0-9]+) x ([0-9]+).*/\1 \2/')
$R "setting-write:outputFolderPath=$out_dir" 10 >/dev/null
read -r crop_file_width crop_file_height <<< "$crop_dimensions"
if [ -n "$crop_file_width" ] && awk "BEGIN { exit !($crop_file_width / $crop_file_height > 1.15 * $(vfield "$picking" source | tr x /)) }"; then pass "video saving while cropping writes only the cropped part (${crop_file_width}x${crop_file_height})"; else fail "video save while cropping" "$crop_dimensions"; fi
click_control "Done" >/dev/null
sleep 1.5
cropped_state=$(video_state)
render=$(vfield "$cropped_state" render)
source_size=$(vfield "$cropped_state" source)
render_width=${render%x*}
source_width=${source_size%x*}
if [ "$(vfield "$cropped_state" tool)" = "select" ] && between "$render_width" "$(( source_width * 62 / 100 ))" "$(( source_width * 68 / 100 ))"; then pass "video \"Done\" shows only the cropped part ($render of $source_size)"; else fail "video cropped preview" "$cropped_state"; fi
click_control "Crop" >/dev/null
sleep 0.8
click_control "Reset" >/dev/null
click_control "Done" >/dev/null
sleep 1.5
reset_state=$(video_state)
if [ "$(vfield "$reset_state" crop)" = "none" ] && [ "$(vfield "$reset_state" render)" = "$(vfield "$reset_state" source)" ]; then pass "video \"Reset\" keeps the whole frame again"; else fail "video reset the crop" "$reset_state"; fi
# Text by a click, typed right on the video: a click with Text used to play the video instead.
area_at() { awk "BEGIN { printf \"%d,%d,%d,%d\", $sx + $sw * $1, $sy + $sh * $2, $sw * $3, $sh * $4 }"; }
$R video-seek:2 10 >/dev/null
click_control "Text" >/dev/null
$R "post-click:$(at 0.3 0.3)" 10 >/dev/null
sleep 1.2
placed=$(video_state)
$R post-text:Total 10 >/dev/null
$R post-key:36:none 10 >/dev/null
sleep 1.5
typed=$(video_state)
if [ "$(vfield "$placed" lastKind)" = "text" ] && [ "$(vfield "$placed" typing)" = "true" ] && [ "$(vfield "$typed" lastText)" = "Total" ] && [ "$(vfield "$typed" typing)" = "false" ] && [ "$(vfield "$typed" playing)" = "false" ]; then pass "video a click with Text places text and it is typed right on the video"; else fail "video text by a click" "$placed / $typed"; fi
text_pixels=$(vfield "$($R "screen-color:$(area_at 0.27 0.27 0.2 0.12):$(vfield "$typed" lastColor)" 20)" coral)
if [ "$(vfield "$typed" typing)" = "false" ] && [ "${text_pixels:-0}" -gt 150 ] 2>/dev/null; then pass "video the typed text shows on the video in the editor"; else fail "video text not shown" "$text_pixels"; fi
# An arrow drawn with the mouse shows in the editor window, not only in the saved file.
click_control "Arrow" >/dev/null
arrow_front=$($R front-app 10)
arrow_hit=$($R "windows-at:$(at 0.55 0.3)" 10)
$R "post-drag:$(at 0.55 0.3):$(at 0.75 0.6)" 10 >/dev/null
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
    sleep 0.8
fi
length_after=$(vfield "$(video_state)" lastLength)
if awk "BEGIN { exit !(${length_after:-0} > ${length_before:-0} + 0.5) }"; then pass "video a mark bar's right edge dragged makes the mark longer"; else fail "video bar edge" "frame=$bx,$by ${bw}x$bh length $length_before → $length_after"; fi
read -r bx by bw bh <<< "$(bar_frame)"
start_before=$(vfield "$(video_state)" lastStart)
if [ -n "$bx" ]; then
    $R "post-drag:$((bx + bw / 2)),$((by + bh / 2)):$((bx + bw / 2 + 50)),$((by + bh / 2))" 10 >/dev/null
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
# Opened for the first time in a run, the window lists its controls after a moment.
shown=""
for _ in 1 2 3 4 5; do
    sleep 1
    shown=$($R controls:settings 30)
    if [[ "$shown" == *"|Include Device"* ]]; then break; fi
done
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
waited=0
while [ -z "$(ls "$out_dir" 2>/dev/null)" ] && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
sleep 1
saved=$(ls "$out_dir" | head -1)
if [[ "$saved" == *.mp4 ]] && $R system-actions:read 10 | grep -q "reveal $out_dir/"; then pass "video \"Save to folder\" exports the edited clip ($saved)"; else fail "video save to folder" "$saved"; fi
printf '' | pbcopy
press_in video: "Copy MP4" >/dev/null
waited=0
while ! $R pasteboard-types 10 | grep -q "file-url" && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
if $R pasteboard-types 10 | grep -q "file-url"; then pass "video \"Copy MP4\" puts the exported file on the clipboard"; else fail "video copy file" "$($R pasteboard-types 10)"; fi
printf '' | pbcopy
$R system-actions:stop 10 >/dev/null
# The next clip opens with the choices changed here: GIF and the keystrokes switch.
press_in video: "GIF" >/dev/null
press_in video: "Show keystrokes" >/dev/null
left=$(video_state)
$R close-windows 10 >/dev/null
$R save:5 60 >/dev/null
sleep 3
opened=$(video_state)
if [ "$(vfield "$opened" format)" = GIF ] && [ "$(vfield "$opened" keys)" = "$(vfield "$left" keys)" ]; then pass "a new clip opens with the last format and switches"; else fail "video editor memory" "$left / $opened"; fi
press_in video: "MP4" >/dev/null
press_in video: "Show keystrokes" >/dev/null
$R close-windows 10 >/dev/null
$R "setting-write:outputFolderPath=$saved_output" 10 >/dev/null

echo "==> the bear stays in sight"
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
sleep 1
if $R windows-debug 10 | tr '|' '\n' | grep "MenuBarExtraWindow" | grep -q "visible=true"; then pass "⌥⇧B opens the Bugbear menu"; else fail "⌥⇧B opens the Bugbear menu"; fi
$R close-panel 10 >/dev/null

echo "==> tooltips"
# Hover a toolbar button in the screenshot editor, and a tab in the menu panel with the app not
# active (how the panel is used): a tooltip appears in both.
$R screenshot-full 40 >/dev/null
sleep 3
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
sleep 1
result=$($R "tooltip-probe:menubar,40,175" 15)
if echo "$result" | grep -q "active=false tooltips=1"; then pass "tooltip in the menu panel while the app is not active"; else fail "tooltip in the menu panel" "$result"; fi
$R close-panel 10 >/dev/null

echo "==> what's new"
$R whats-new 10 >/dev/null
if $R windows-debug 10 | tr '|' '\n' | grep "visible=true" | grep -q "720x"; then pass "What's New window opens"; else fail "What's New window"; fi
$R close-windows 10 >/dev/null

echo "==> welcome guide fits the screen"
# Opened fresh, the guide keeps its own size and stays inside the screen, so Continue is reachable.
frame_key="NSWindow Frame Bugbear.onboarding"
defaults delete "$BUNDLE_ID" "$frame_key" 2>/dev/null
result=$($R open-onboarding 10)
if python3 scripts/test/lib/window-fits.py "$result"; then pass "welcome guide fits the screen ($result)"; else fail "welcome guide fits the screen" "$result"; fi
$R close-windows 10 >/dev/null
defaults delete "$BUNDLE_ID" "$frame_key" 2>/dev/null

echo "==> report a problem"
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
if [[ "$result" == *"bugbear.log"* && "$result" == *"environment.txt"* && "$result" == *"planted=true home=false user=false" ]]; then pass "the log zip has the log and the environment, hides the home folder and user name ($result)"; else fail "the log zip" "$result"; fi
result=$($R feedback-crash:on 15)
if [[ "$result" == "offered=true open=true crash=true canSend=true moved=true title=$APP_NAME quit unexpectedly" ]]; then pass "a crash since the last launch opens a report with the crash filled in ($result)"; else fail "a crash opens a report" "$result"; fi
result=$($R feedback-crash:off 15)
if [[ "$result" == "offered=false open=false crash=false canSend=false moved=true title=" ]]; then pass "with crash reports turned off nothing opens, and the crash is not offered later ($result)"; else fail "crash reports turned off" "$result"; fi
result=$($R feedback-switch 10)
if [[ "$result" == "kind=idea" ]]; then pass "asking for an idea while the problem window is open shows the idea form"; else fail "switching the feedback window" "$result"; fi

echo "==> disk space"
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
sleep 1
if $R windows-debug 10 | tr '|' '\n' | grep "visible=true" | grep -q "level=0"; then pass "Space window opens"; else fail "Space window"; fi
$R close-windows 10 >/dev/null

# Close the test page window, and only that one.
$R "activate-app:$BROWSER" 10 >/dev/null
if $R front-title 10 | grep -q "^title=Scroll test"; then
    $R post-key:13:cmd 10 >/dev/null
fi

$R setting:readBrowserURL:true 10 >/dev/null
$R browser-accessibility-off 10 >/dev/null

echo "==> quitting stops the screen capture"
# pkill (updates, reinstalls) used to end Bugbear mid-capture, and macOS kept showing
# "Bugbear - Currently Sharing" after it was gone.
$R buffer-start 30 >/dev/null
log_lines_before=$(wc -l < "$LOG")
pkill -x Bugbear 2>/dev/null
# It has to quit by itself: wait_for_bugbear_to_quit would end it with kill -9 and hide a hang.
waited=0
while pgrep -x Bugbear >/dev/null && [ "$waited" -lt 30 ]; do
    sleep 0.2
    waited=$((waited + 1))
done
if pgrep -x Bugbear >/dev/null; then quit_by_itself=false; else quit_by_itself=true; fi
wait_for_bugbear_to_quit
quit_log=$(tail -n +"$((log_lines_before + 1))" "$LOG")
if [ "$quit_by_itself" = true ]; then pass "Bugbear quits on SIGTERM"; else fail "Bugbear quits on SIGTERM" "still running after 6 s"; fi
if echo "$quit_log" | grep -q "quit requested by SIGTERM" && echo "$quit_log" | grep -q "capture stopped for quit" && ! echo "$quit_log" | grep -q "quit timed out" && ! echo "$quit_log" | grep -q "quit did not finish"; then pass "SIGTERM stops the screen capture before quitting"; else fail "SIGTERM stops the screen capture" "$quit_log"; fi

defaults write "$BUNDLE_ID" automationEnabled -bool false
# Bugbear has quit above, so its captures can go from disk; it reads the folder on the next launch.
removed=0
while IFS= read -r folder_name; do
    if [ -z "$folder_name" ] || grep -qxF "$folder_name" "$WORK/captures-before.txt"; then continue; fi
    rm -rf "${CAPTURES_DIR:?}/$folder_name"
    removed=$((removed + 1))
done < <(ls "$CAPTURES_DIR" 2>/dev/null)
echo "removed $removed captures the tests made"
pbcopy < "$WORK/clipboard-before.txt"
if [ "$(defaults read "$BUNDLE_ID" recentAnnotationColors 2>/dev/null)" = "$(cat "$WORK/palette-before.txt")" ]; then pass "the tests leave the person's editor colors as they were"; else fail "editor colors changed by the tests" "$(defaults read "$BUNDLE_ID" recentAnnotationColors 2>/dev/null | tr -d '\n ')"; fi
echo
echo "$PASSES passed, $FAILURES failed."
[ "$FAILURES" = "0" ]
