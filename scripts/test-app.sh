# Sourced by the scripts that test the real app (e2e.sh, e2e-features.sh, perf.sh).
# A test run uses the build in build/, so an installed Bugbear has to step aside: it is quit before
# the run and started again afterwards, and the test copy never stays behind in the menu bar.
#
#   quit_running_bugbear      # remembers which Bugbear was running, quits it, cleans up on exit
#   open "$TEST_APP"          # then start the test copy

TEST_APP="$ROOT/build/Bugbear.app"
INSTALLED_APP=""

quit_running_bugbear() {
    local pid
    for pid in $(pgrep -x Bugbear); do
        local executable
        executable="$(ps -o comm= -p "$pid")"
        case "$executable" in
            "$TEST_APP"/*) ;;
            *) INSTALLED_APP="${executable%%/Contents/MacOS/*}" ;;
        esac
    done
    pkill -x Bugbear 2>/dev/null
    sleep 1
    trap restore_running_bugbear EXIT
}

restore_running_bugbear() {
    pkill -f "$TEST_APP/Contents/MacOS/Bugbear" 2>/dev/null
    if [ -n "$INSTALLED_APP" ] && [ -d "$INSTALLED_APP" ]; then
        sleep 1
        open "$INSTALLED_APP"
        echo "==> started $INSTALLED_APP again"
    fi
}
