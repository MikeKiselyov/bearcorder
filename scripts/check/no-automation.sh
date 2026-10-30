#!/bin/bash
# A release build has no automation hook, self-test or media tools: nothing outside can drive it.
# Builds a release binary the way scripts/build-app.sh does (in a build folder of its own, so the
# app the tests drive is left alone) and looks for texts only those tools have. The same texts
# must be in a debug build, which has the tools: otherwise this list is out of date and would
# find nothing in any build.
#
#   scripts/check/no-automation.sh
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

# Long enough that Swift keeps them as C strings, where `strings` sees them.
MARKERS=(
    "automation: could not write result"
    "automationEnabled"
    "README media written to"
    "Snapshots written to"
)

# The markers a binary has, one per line.
markers_in() {
    local listing
    listing="$(mktemp)"
    strings "$1" > "$listing"
    for marker in "${MARKERS[@]}"; do
        if grep -qF -- "$marker" "$listing"; then
            echo "$marker"
        fi
    done
    rm -f "$listing"
}

SCRATCH="$ROOT/.build/no-automation-check"
BUILD_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG"' EXIT
# build <swift build arguments>: quiet, with the output shown when it fails.
build() {
    if ! swift build "$@" >"$BUILD_LOG" 2>&1; then
        cat "$BUILD_LOG" >&2
        die "swift build $* failed"
    fi
}
build -c release --product App --scratch-path "$SCRATCH"
release="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/App"
build --product App
debug="$(swift build --show-bin-path)/App"

in_debug="$(markers_in "$debug")"
if [ "$(echo "$in_debug" | grep -c .)" != "${#MARKERS[@]}" ]; then
    die "the debug build lacks some markers (found: ${in_debug//$'\n'/, }); update MARKERS"
fi
in_release="$(markers_in "$release")"
if [ -n "$in_release" ]; then
    die "the release binary has automation in it: ${in_release//$'\n'/, }"
fi
if "$release" --self-test /dev/null >/dev/null 2>&1; then
    die "the release binary accepts --self-test"
fi
"$release" --version >/dev/null
echo "release has no automation"
