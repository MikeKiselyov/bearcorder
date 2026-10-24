#!/bin/bash
# Every test suite in one run, with a summary at the end.
#
#   scripts/test-all.sh           # everything (~8 min): needs Screen Recording and Accessibility,
#                                 # opens a Chrome window and moves the mouse, so don't touch the Mac
#   scripts/test-all.sh --quick   # unit tests and the self-test only (~1 min), no permissions needed
#
# Suites:
#   unit       swift test: parsers, converters, reports, timelines, disk tree (BugbearCore)
#   self-test  media pipeline: export, edits, GIF, size limits, annotations, OCR, QR, stitching
#   e2e        the real app: buffer, saving, recording with pause, audio, markers, crash watch, updates
#   features   the real app with a browser: scrolling screenshot, ruler, color picker, overlay,
#              area recording, shortcuts, reports, displays, menu panel, disk space
#   perf       CPU and memory while idle and recording, save speed
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
LOGS="$ROOT/build/test-logs"
rm -rf "$LOGS"
mkdir -p "$LOGS"

QUICK=0
if [ "${1:-}" = "--quick" ]; then
    QUICK=1
fi

NAMES=()
RESULTS=()
TIMES=()

# run_suite <name> <command...>: runs it with the output in a log, keeps a one-line result.
run_suite() {
    local name="$1"
    shift
    local log="$LOGS/$name.log"
    local started
    started=$(date +%s)
    echo "==> $name"
    "$@" >"$log" 2>&1
    local status=$?
    local seconds=$(($(date +%s) - started))
    local summary
    summary=$(grep -E "passed, [0-9]+ failed|Executed [0-9]+ tests|ALL CHECKS PASSED|ALL PERFORMANCE CHECKS PASSED|FAILED" "$log" | tail -1 | sed -E 's/^[[:space:]]+//')
    if [ "$status" = "0" ]; then
        echo "    ok - $summary (${seconds}s)"
        RESULTS+=("ok    $summary")
    else
        echo "    FAILED - see $log"
        grep -E "^FAIL|error:|failed \(" "$log" | head -15 | sed 's/^/    /'
        RESULTS+=("FAIL  ${summary:-exit $status}")
    fi
    NAMES+=("$name")
    TIMES+=("$seconds")
}

self_test() {
    local folder="$ROOT/build/self-test"
    rm -rf "$folder"
    mkdir -p "$folder"
    swift build -c debug >/dev/null || return 1
    .build/debug/Bugbear --self-test "$folder"
}

run_suite unit swift test
run_suite self-test self_test
if [ "$QUICK" = "0" ]; then
    run_suite e2e scripts/e2e.sh
    run_suite features scripts/e2e-features.sh
    run_suite perf scripts/perf.sh
fi

echo
echo "Summary"
failed=0
for index in "${!NAMES[@]}"; do
    printf '  %-10s %-60s %4ss\n' "${NAMES[$index]}" "${RESULTS[$index]}" "${TIMES[$index]}"
    case "${RESULTS[$index]}" in
        FAIL*) failed=1 ;;
    esac
done
echo "Logs: $LOGS"
if [ "$QUICK" = "1" ]; then
    echo "Quick run: e2e, features and perf were skipped."
fi
exit "$failed"
