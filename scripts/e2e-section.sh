#!/bin/bash
# Runs one section of scripts/e2e-features.sh against a fresh test build, for working on it.
# A section starts at its `echo "==> <title>"` line and ends at the next one.
#
#   scripts/e2e-section.sh "menu panel buttons: Capture"
#
# Sections that need the browser test page from earlier sections are not meant for this.
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
LOG="$HOME/Library/Logs/Bugbear/bugbear.log"
FAILURES=0
PASSES=0
pass() { echo "PASS  $1"; PASSES=$((PASSES + 1)); }
fail() { echo "FAIL  $1 ${2:-}"; FAILURES=$((FAILURES + 1)); }
field() { echo "$1" | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }
# shellcheck disable=SC1091
source "$ROOT/scripts/e2e-helpers.sh"

title="${1:?section title}"
section=$(mktemp)
awk -v start="echo \"==> $title\"" '
    index($0, start) == 1 { inside = 1; print; next }
    inside && /^echo "==> / { exit }
    inside { print }
' scripts/e2e-features.sh > "$section"
if [ ! -s "$section" ]; then
    echo "no section \"$title\""
    exit 2
fi

scripts/build-app.sh >/dev/null 2>&1 || { echo "build failed"; exit 1; }
# Quit the person's Bugbear and keep a copy of their settings before any test setting is written.
quit_running_bugbear
mkdir -p "$WORK"
defaults write "$BUNDLE_ID" automationEnabled -bool true
# Editor choices made by the tests go to a store of their own (EditorMemory); start it empty.
defaults delete "$BUNDLE_ID.tests" 2>/dev/null
open "$TEST_APP"
sleep 7
# shellcheck disable=SC1090
source "$section"
rm -f "$section"
defaults write "$BUNDLE_ID" automationEnabled -bool false
echo
echo "$PASSES passed, $FAILURES failed."
[ "$FAILURES" = "0" ]
