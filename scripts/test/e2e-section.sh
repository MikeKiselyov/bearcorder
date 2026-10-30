#!/bin/bash
# Runs one section of scripts/test/e2e-features.sh against a fresh test build, for working on it.
# A section starts at its `section "<title>"` line and ends at the next one.
#
#   scripts/test/e2e-section.sh "menu panel buttons: Capture"
#
# Sections that need the browser test page from earlier sections are not meant for this.
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
# BROWSER and LOG are for the section file sourced below.
# shellcheck disable=SC2034
BROWSER="${E2E_BROWSER:-Google Chrome}"
WORK="$ROOT/build/e2e-features"
# shellcheck disable=SC2034
LOG="$HOME/Library/Logs/$APP_NAME/$APP_NAME.log"
FAILURES=0
PASSES=0
pass() { echo "PASS  $1"; PASSES=$((PASSES + 1)); }
fail() { echo "FAIL  $1 ${2:-}"; FAILURES=$((FAILURES + 1)); }
field() { echo "$1" | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }
# shellcheck disable=SC1091
source "$ROOT/scripts/test/lib/e2e-helpers.sh"

title="${1:?section title}"
section=$(mktemp)
awk -v start="section \"$title\"" '
    index($0, start) == 1 { inside = 1; print; next }
    inside && /^section "/ { exit }
    inside { print }
' scripts/test/e2e-features.sh > "$section"
if [ ! -s "$section" ]; then
    echo "no section \"$title\""
    exit 2
fi

build_test_app || exit 1
# Quit the person's copy of the app and keep a copy of their settings before any test setting is written.
quit_running_app
mkdir -p "$WORK"
defaults write "$BUNDLE_ID" automationEnabled -bool true
# Editor choices made by the tests go to a store of their own (EditorMemory); start it empty.
defaults delete "$BUNDLE_ID.tests" 2>/dev/null
open "$TEST_APP"
# The app answers and its buffer has started.
wait_for 20 status_starts running
# shellcheck disable=SC1090
source "$section"
rm -f "$section"
print_section_times
defaults write "$BUNDLE_ID" automationEnabled -bool false
echo
echo "$PASSES passed, $FAILURES failed."
[ "$FAILURES" = "0" ]
