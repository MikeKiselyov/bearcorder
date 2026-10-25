#!/bin/bash
# Real-screen checks of the features that need other apps and the mouse: scrolling screenshot of a
# browser page, window resizing, ruler, color picker, design overlay, area recording through the
# picker, shortcuts, reports, step guide, comparison, editor sizes.
#
#   scripts/e2e-features.sh                     # in Google Chrome
#   E2E_BROWSER=Safari scripts/e2e-features.sh  # or another browser
#
# Opens a local test page in a new browser window and moves the mouse; don't touch the Mac while it runs (~2 min).
# Needs Screen Recording and Accessibility for Bugbear. Restores the settings it changes.
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
# shellcheck disable=SC1091
source "$ROOT/scripts/test-app.sh"
R=scripts/bugbear-run.sh
BROWSER="${E2E_BROWSER:-Google Chrome}"
WORK="$ROOT/build/e2e-features"
FAILURES=0
PASSES=0

pass() { echo "PASS  $1"; PASSES=$((PASSES + 1)); }
fail() { echo "FAIL  $1 ${2:-}"; FAILURES=$((FAILURES + 1)); }
field() { echo "$1" | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

echo "==> build and launch"
scripts/build-app.sh >/dev/null 2>&1 || { echo "build failed"; exit 1; }
rm -rf "$WORK"
mkdir -p "$WORK"
defaults write "$BUNDLE_ID" automationEnabled -bool true
quit_running_bugbear
open "$TEST_APP"
sleep 6
$R setting:readBrowserURL:false 10 >/dev/null
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
# Resizing, moving and scrolling act on the front window: only ever on the test page.
title=$($R front-title 10 | sed -n 's/^title=//p')
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
for attempt in 1 2 3 4 5; do
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
result=$($R scroll-capture:$area 300)
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
    $R post-click:$footer_point 10 >/dev/null
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
$R post-click:$chip 10 >/dev/null
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
$R fields:Stand=stage-3,Build=1.42 10 >/dev/null
$R screenshot-full 40 >/dev/null
$R close-windows 10 >/dev/null
if [ "$($R extras-latest 10)" = "extras=Stand=stage-3,Build=1.42" ]; then pass "report fields saved with the capture"; else fail "report fields"; fi
$R report:jira 10 >/dev/null
if pbpaste | grep -q "^\* \*Stand:\* stage-3"; then pass "Jira wiki report"; else fail "Jira wiki report"; fi
$R report:markdown 10 >/dev/null
if pbpaste | grep -q "^## Steps to reproduce"; then pass "Markdown report"; else fail "Markdown report"; fi
$R fields: 10 >/dev/null
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
result=$($R cleanup-dryrun:0:0 60)
if echo "$result" | grep -q "wouldDelete=0"; then pass "clean-up with no limits deletes nothing"; else fail "clean-up dry run" "$result"; fi

echo "==> several displays"
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
    $R screenshot-full 40 >/dev/null
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

echo "==> tooltips"
# Hover a toolbar button in the screenshot editor, and a tab in the menu panel with the app not
# active (how the panel is used): a tooltip appears in both.
$R screenshot-full 40 >/dev/null
sleep 3
result=$($R "tooltip-probe:screenshot,120,82" 15)
if echo "$result" | grep -q "tooltips=1"; then pass "tooltip on an editor tool"; else fail "tooltip on an editor tool" "$result"; fi
result=$($R editor-checks 30)
if echo "$result" | grep -q "sizeFollowsTool=true"; then pass "one size control: text size for text, line width for shapes"; else fail "size control" "$result"; fi
if echo "$result" | grep -q "sizeFollowsSelection=true"; then pass "the size control shows and changes the selected mark"; else fail "size control with a selection" "$result"; fi
if echo "$result" | grep -q "typingNoFillAtOnce=true"; then pass "No fill takes the label off text while typing"; else fail "No fill while typing" "$result"; fi
if echo "$result" | grep -q "textDrawnOnce=true"; then pass "text being typed is drawn once, not twice"; else fail "text drawn twice while typing" "$result"; fi
if echo "$result" | grep -q "pasteImage=true"; then pass "⌘V places a picture on the screenshot"; else fail "paste a picture" "$result"; fi
if echo "$result" | grep -q "deleteInEditorWindow=true"; then pass "Delete in the editor window removes the selected mark with the focus away from the canvas"; else fail "Delete key" "$result"; fi
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
if python3 scripts/window-fits.py "$result"; then pass "welcome guide fits the screen ($result)"; else fail "welcome guide fits the screen" "$result"; fi
$R close-windows 10 >/dev/null
defaults delete "$BUNDLE_ID" "$frame_key" 2>/dev/null

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
rm -rf "$fixture"
result=$($R space-clean-test 60)
if echo "$result" | grep -q "cacheGone=true homebrewKept=true otherLogGone=true ownLogKept=true cachesFolderKept=true crashReportsKept=true"; then pass "clean-up deletes caches and keeps what it must"; else fail "clean-up" "$result"; fi
result=$($R space-stop-test 120)
if echo "$result" | grep -q "afterStop=idle final=done"; then pass "stopped scan leaves no stale result"; else fail "stop scan" "$result"; fi
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
defaults write "$BUNDLE_ID" automationEnabled -bool false
echo
echo "$PASSES passed, $FAILURES failed."
[ "$FAILURES" = "0" ]
