# shellcheck shell=bash
# Sourced by scripts/test/e2e-features.sh and scripts/test/e2e-section.sh: pressing controls and reading
# what they did. Needs R (scripts/dev/bugbear-run.sh).

# press_menu <tab> <label>: opens the menu bar panel on a tab and presses a control in it, the
# way VoiceOver presses it. Prints "pressed" or "not found".
press_menu() {
    $R close-panel 10 >/dev/null
    $R press-status-item 10 >/dev/null
    $R "press:menubar:$1" 10 >/dev/null
    $R "press:menubar:$2" 15
}

# How many captures there are.
capture_count() { $R status 10 | sed -n 's/.*captures=\([0-9]*\).*/\1/p'; }

# The app's visible windows, by id: "settings;feedback;screenshot:…".
windows_now() { $R visible-windows 10; }

# Drawing, ruler, color loupe and recording state.
tools_now() { $R screen-tools 10; }

# press_in <window> <label>: presses a control in an app window (settings, history, …).
press_in() { $R "press:$1:$2" 15; }

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
    sleep 1
    $R tall-window:settings 10 >/dev/null
}
