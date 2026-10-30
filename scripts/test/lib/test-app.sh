# shellcheck shell=bash
# Sourced by the scripts that test the real app (e2e.sh, e2e-features.sh, perf.sh).
# A test run uses the build in build/, so an installed copy has to step aside: it is quit before
# the run and started again afterwards, and the test copy never stays behind in the menu bar.
#
#   quit_running_app      # remembers which copy was running, quits it, cleans up on exit
#   open "$TEST_APP"          # then start the test copy

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/app-name.sh"
TEST_APP="$ROOT/build/$APP_NAME.app"
# The tests drive the app through its automation hook, which only this build has (build-app.sh).
export APP_AUTOMATION=1
INSTALLED_APP=""

# build_test_app: builds the test app, unless all.sh did it already (APP_BUILT=1): then the
# build in build/ is used as it is, and the run stops when there is none.
build_test_app() {
    if [ "${APP_BUILT:-}" = "1" ]; then
        if [ ! -d "$TEST_APP" ]; then
            echo "$TEST_APP missing: run scripts/build-app.sh first"
            return 1
        fi
        # A stale or release build (APP_BUILT left over in a shell) has no marker.
        if [ ! -f "$ROOT/build/.automation-build" ]; then
            echo "$TEST_APP is not a build with automation: run APP_AUTOMATION=1 scripts/build-app.sh first"
            return 1
        fi
        return 0
    fi
    "$ROOT/scripts/build-app.sh" >/dev/null 2>&1 || { echo "build failed"; return 1; }
}

# The app stops its screen capture before it quits (up to 2 s), so wait for it to be gone.
wait_for_app_to_quit() {
    local tries=0
    while pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$tries" -lt 50 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    # Still there (stuck in a modal alert): it must not keep running from a replaced app.
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        pkill -9 -x "$APP_NAME" 2>/dev/null || true
        sleep 0.5
    fi
}

# The person's settings as they were before the run. Tests change settings and put them back,
# but a stopped run never gets there: on exit the whole domain is put back from this copy.
SETTINGS_SNAPSHOT=""
SETTINGS_EXISTED=0

save_settings() {
    local domain="$1"
    SETTINGS_SNAPSHOT="$(mktemp -t "$APP_SLUG-settings")"
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

quit_running_app() {
    local pid
    for pid in $(pgrep -x "$APP_NAME"); do
        local executable
        executable="$(ps -o comm= -p "$pid")"
        case "$executable" in
            "$TEST_APP"/*) ;;
            *) INSTALLED_APP="${executable%%/Contents/MacOS/*}" ;;
        esac
    done
    pkill -x "$APP_NAME" 2>/dev/null
    wait_for_app_to_quit
    # After the quit, so the copy is what the person last had.
    save_settings "$BUNDLE_ID"
    trap restore_running_app EXIT
}

restore_running_app() {
    pkill -f "$TEST_APP/Contents/MacOS/$APP_NAME" 2>/dev/null
    # Before the person's copy starts, so it reads its own settings, not the test's.
    wait_for_app_to_quit
    restore_settings "$BUNDLE_ID"
    if [ -n "$INSTALLED_APP" ] && [ -d "$INSTALLED_APP" ]; then
        wait_for_app_to_quit
        open "$INSTALLED_APP"
        echo "==> started $INSTALLED_APP again"
    fi
}
