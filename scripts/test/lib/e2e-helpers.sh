# shellcheck shell=bash
# Sourced by scripts/test/e2e.sh, e2e-features.sh and e2e-section.sh: pressing controls and reading
# what they did. Needs R (scripts/dev/app-run.sh).

# wait_for <timeout seconds> <command...>: runs the command every 0.1 s until it succeeds or the
# timeout passes. The timeout is a deadline on the clock, not a number of tries, so a slow command
# (a hung app answers only after $R's own timeout) cannot stretch the wait; SECONDS counts whole
# seconds, so the wait lasts between <timeout> and <timeout>+1 s plus the last command, never less.
# Returns 0 when it succeeded, 1 on timeout. The caller's check after it still decides pass or
# fail, so a timeout ends in the same "fail" the check gave before.
wait_for() {
    local timeout="$1"
    shift
    local deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -le "$deadline" ]; do
        if "$@" >/dev/null 2>&1; then return 0; fi
        # Poll step.
        sleep 0.1
    done
    return 1
}

# wait_for_value <timeout> <expected> <command...>: until the command prints exactly <expected>.
wait_for_value() {
    local timeout="$1"
    local expected="$2"
    shift 2
    local deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -le "$deadline" ]; do
        if [ "$("$@" 2>/dev/null)" = "$expected" ]; then return 0; fi
        # Poll step.
        sleep 0.1
    done
    return 1
}

# wait_for_text <timeout> <needle> <command...>: until the command's output contains <needle>.
wait_for_text() {
    local timeout="$1"
    local needle="$2"
    shift 2
    local deadline=$((SECONDS + timeout))
    local output
    while [ "$SECONDS" -le "$deadline" ]; do
        output=$("$@" 2>/dev/null)
        if [[ "$output" == *"$needle"* ]]; then return 0; fi
        # Poll step.
        sleep 0.1
    done
    return 1
}

# wait_for_no_text <timeout> <needle> <command...>: until the command's output no longer contains <needle>.
wait_for_no_text() {
    local timeout="$1"
    local needle="$2"
    shift 2
    local deadline=$((SECONDS + timeout))
    local output
    while [ "$SECONDS" -le "$deadline" ]; do
        output=$("$@" 2>/dev/null)
        if [[ "$output" != *"$needle"* ]]; then return 0; fi
        # Poll step.
        sleep 0.1
    done
    return 1
}

# Conditions for wait_for (each succeeds when the state is there).
# The test browser is the front app.
browser_is_front() { [ "$($R front-app 10)" = "$BROWSER" ]; }
wait_browser_front() { wait_for 10 browser_is_front; }
# The area picker has a selection (a size chip was clicked).
picker_selected() { local shown; shown=$($R picker-selection 10); [ -n "$shown" ] && [ "$shown" != none ]; }
# A setting differs from a value read before.
setting_differs() { [ "$(setting_value "$1")" != "$2" ]; }
# The status line starts with a word ("running", "paused").
status_starts() { [[ "$($R status 10)" == "$1"* ]]; }
# More "marker added" lines in the log than a count read before.
marker_count_above() { [ "$(grep -c "marker added" "$LOG")" -gt "$1" ]; }
# More buffer "started" lines in the log than a count read before.
buffer_started_above() { [ "$(grep -c "buffer\[.*\] started" "$LOG")" -gt "$1" ]; }
# A line is in the last 20 lines of the log.
recent_log_has() { tail -20 "$LOG" | grep -q "$1"; }
# The menu bar panel lists a recent capture.
recent_capture_shown() { $R controls:menubar 30 | sed 's/ ;; /\n/g' | grep -qE "(ago|just now)$"; }
# A capture editor window is open.
capture_editor_open() { local windows; windows=$(windows_now); [[ "$windows" == *"screenshot:"* || "$windows" == *"video:"* ]]; }
# The menu bar panel window is visible.
menu_panel_open() { $R windows-debug 10 | tr '|' '\n' | grep "MenuBarExtraWindow" | grep -q "visible=true"; }
# The number of report fields differs from a count read before.
fields_count_not() { [ "$($R fields-count 10)" != "$1" ]; }
# buffer_holds <seconds>: the main display's buffer holds at least that much video (buffer-seconds).
buffer_holds() { awk -v held="$($R buffer-seconds 10)" -v wanted="$1" 'BEGIN { exit !(held + 0 >= wanted + 0) }'; }
# A folder has something in it.
dir_has_file() { [ -n "$(ls "$1" 2>/dev/null)" ]; }

# press_menu <tab> <label>: opens the menu bar panel on a tab and presses a control in it, the
# way VoiceOver presses it. One command in the app (press-menu). Prints "pressed", "not found", or
# "tab not found: <tab>" when the tab is not there (the label is then not pressed at all).
press_menu() {
    $R "press-menu:$1:$2" 15
}

# How many captures there are.
capture_count() { $R status 10 | sed -n 's/.*captures=\([0-9]*\).*/\1/p'; }

# The app's visible windows, by id: "settings;feedback;screenshot:…".
windows_now() { $R visible-windows 10; }

# window_open <id>: a window with exactly this id is visible (not one whose id only contains it).
window_open() { windows_now | tr ';' '\n' | grep -qxF "$1"; }

# space_control_shown <label>: the Disk Space window has a control with exactly this label, so
# "Find projects" is not satisfied by "Find projects…" on the row before the list opens.
space_control_shown() { $R controls:space 30 | sed 's/ ;; /\n/g' | cut -d'|' -f2- | grep -qxF "$1"; }

# Drawing, ruler, color loupe and recording state.
tools_now() { $R screen-tools 10; }

# press_in <window> <label>: presses a control in an app window (settings, history, …).
press_in() { $R "press:$1:$2" 15; }
# press_now <window> <label>: the same press, answered right away instead of after the app's moment
# for redrawing. Only where the next step waits for what the press does (wait_for and siblings).
press_now() { $R "press-now:$1:$2" 15; }

# setting_value <key>: the value the running app uses, its default when never changed (booleans
# read 1 or 0). Read inside the app: defaults on disk do not show defaults never changed.
setting_value() { $R "setting-read:$1" 10; }

# picker_round_trip <window> <label>: picks another item of a picker and then the first one again,
# reading what the picker shows each time. Prints "ok <first> → <other>" or what went wrong.
picker_round_trip() {
    local shown other now back
    shown=$($R "control-value:$1:$2" 10)
    shown="${shown#value=}"
    other=$($R "menu-items:$1:$2" 10 | sed 's/ ;; /\n/g' | grep -vxF "$shown" | head -1)
    $R "choose:$1:$2 => $other" 10 >/dev/null
    now=$($R "control-value:$1:$2" 10)
    now="${now#value=}"
    $R "choose:$1:$2 => $shown" 10 >/dev/null
    back=$($R "control-value:$1:$2" 10)
    back="${back#value=}"
    if [ -n "$other" ] && [ "$now" = "$other" ] && [ "$back" = "$shown" ]; then
        echo "ok $shown → $other"
    else
        echo "no: shown \"$shown\", other \"$other\", then \"$now\", back \"$back\""
    fi
}

# open_settings: the Settings window alone, tall enough that every row is built.
open_settings() {
    $R close-windows 10 >/dev/null
    press_menu Capture "Open settings: buffer, shortcuts, storage and more" >/dev/null
    wait_for_text 10 settings windows_now
    $R tall-window:settings 10 >/dev/null
}

# section "<title>": prints the header e2e-section.sh finds the section by, and keeps how long the
# section before it took. The summary at the end lists them, slowest first.
SECTION_NAMES=()
SECTION_SECONDS=()
CURRENT_SECTION=""
SECTION_START=$SECONDS
section() {
    finish_section
    CURRENT_SECTION="$1"
    SECTION_START=$SECONDS
    echo "==> $1"
}
finish_section() {
    if [ -n "$CURRENT_SECTION" ]; then
        SECTION_NAMES+=("$CURRENT_SECTION")
        SECTION_SECONDS+=("$((SECONDS - SECTION_START))")
    fi
    CURRENT_SECTION=""
}
print_section_times() {
    finish_section
    echo
    echo "Section times, slowest first:"
    local index
    for index in "${!SECTION_NAMES[@]}"; do
        printf '%6ds  %s\n' "${SECTION_SECONDS[$index]}" "${SECTION_NAMES[$index]}"
    done | sort -rn
}
