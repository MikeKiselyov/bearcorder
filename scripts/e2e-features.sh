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
pkill -x Bugbear 2>/dev/null; sleep 1
open "$ROOT/build/Bugbear.app"
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
if [ "$BROWSER" = "Google Chrome" ]; then
    # Hands the page to the running Chrome, which opens it in a new window.
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --new-window "file://$WORK/long.html" >/dev/null 2>&1 &
else
    open -a "$BROWSER" "$WORK/long.html"
fi
sleep 4
$R "activate-app:$BROWSER" 10 >/dev/null
sleep 1
# Resizing and moving act on the front app: never touch someone else's window.
front=$($R screen 10 | sed -n 's/.*front=//p')
if [ "$front" != "$BROWSER" ]; then
    echo "STOP  $BROWSER is not in front ($front is), so windows are left alone."
    $R setting:readBrowserURL:true 10 >/dev/null
    defaults write "$BUNDLE_ID" automationEnabled -bool false
    exit 1
fi

echo "==> window size"
result=$($R resize-front:1280x720 10)
if echo "$result" | grep -q "app=$BROWSER size=1280x720"; then pass "resize $BROWSER to 1280×720"; else fail "resize $BROWSER" "$result"; fi
$R resize-front:1100x760 10 >/dev/null
$R move-front:120,60 10 >/dev/null
sleep 1

echo "==> scrolling screenshot"
$R post-key:115:none 10 >/dev/null
sleep 1
# The page area from Accessibility, minus 24 pt on the right for the scroll bar.
web=$($R web-area 10)
screen_width=$($R screen 10 | sed -n 's/width=\([0-9]*\).*/\1/p')
screen_height=$($R screen 10 | sed -n 's/.*height=\([0-9]*\).*/\1/p')
area=$(echo "$web" | awk -F, -v width="$screen_width" '{ printf "%.4f,%.4f,%.4f,%.4f", $1, $2, $3 - 24 / width, $4 }')
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
footer_point=$(echo "$web" | awk -F, -v width="$screen_width" -v height="$screen_height" '{ printf "%d,%d", ($1 + $3 / 2) * width, ($2 + $4) * height - 20 }')
$R post-click:$footer_point 10 >/dev/null
wait
if grep -q "hex=#FF6B4A" "$WORK/pick.txt"; then pass "picks #FF6B4A from the footer"; else fail "color picker" "$(cat "$WORK/pick.txt")"; fi

echo "==> ruler"
$R ruler-start 10 >/dev/null
$R post-drag:400,300:700,500 10 >/dev/null
$R "activate-app:$BROWSER" 10 >/dev/null
sleep 1
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

$R setting:readBrowserURL:true 10 >/dev/null
defaults write "$BUNDLE_ID" automationEnabled -bool false
echo
echo "$PASSES passed, $FAILURES failed."
[ "$FAILURES" = "0" ]
