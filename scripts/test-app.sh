# Sourced by the scripts that test the real app (e2e.sh, e2e-features.sh, perf.sh).
# A test run uses the build in build/, so an installed Bugbear has to step aside: it is quit before
# the run and started again afterwards, and the test copy never stays behind in the menu bar.
#
#   quit_running_bugbear      # remembers which Bugbear was running, quits it, cleans up on exit
#   open "$TEST_APP"          # then start the test copy

# shellcheck disable=SC1091
source "$ROOT/scripts/app-name.sh"
TEST_APP="$ROOT/build/$APP_NAME.app"
INSTALLED_APP=""

# Bugbear stops its screen capture before it quits (up to 2 s), so wait for it to be gone.
wait_for_bugbear_to_quit() {
    local tries=0
    while pgrep -x Bugbear >/dev/null 2>&1 && [ "$tries" -lt 50 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    # Still there (stuck in a modal alert): it must not keep running from a replaced app.
    if pgrep -x Bugbear >/dev/null 2>&1; then
        pkill -9 -x Bugbear 2>/dev/null || true
        sleep 0.5
    fi
}

# The person's settings as they were before the run. Tests change settings and put them back,
# but a stopped run never gets there: on exit the whole domain is put back from this copy.
SETTINGS_SNAPSHOT=""
SETTINGS_EXISTED=0

save_settings() {
    local domain="$1"
    SETTINGS_SNAPSHOT="$(mktemp -t bugbear-settings)"
    if defaults export "$domain" "$SETTINGS_SNAPSHOT" 2>/dev/null; then
        SETTINGS_EXISTED=1
    else
        SETTINGS_EXISTED=0
    fi
}

restore_settings() {
    local domain="$1"
    if [ -z "$SETTINGS_SNAPSHOT" ]; then
        return
    fi
    defaults delete "$domain" 2>/dev/null || true
    if [ "$SETTINGS_EXISTED" = "1" ]; then
        defaults import "$domain" "$SETTINGS_SNAPSHOT"
    fi
    rm -f "$SETTINGS_SNAPSHOT"
    SETTINGS_SNAPSHOT=""
}

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
    wait_for_bugbear_to_quit
    # After the quit, so the copy is what the person last had.
    save_settings "$BUNDLE_ID"
    trap restore_running_bugbear EXIT
}

restore_running_bugbear() {
    pkill -f "$TEST_APP/Contents/MacOS/Bugbear" 2>/dev/null
    # Before the person's Bugbear starts, so it reads its own settings, not the test's.
    wait_for_bugbear_to_quit
    restore_settings "$BUNDLE_ID"
    if [ -n "$INSTALLED_APP" ] && [ -d "$INSTALLED_APP" ]; then
        wait_for_bugbear_to_quit
        open "$INSTALLED_APP"
        echo "==> started $INSTALLED_APP again"
    fi
}
