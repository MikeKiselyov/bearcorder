# shellcheck shell=bash
# Sourced by build-app.sh --install and update.sh, after scripts/lib/app-name.sh (APP_NAME, APP_SLUG).
#
#   replace_app <new app> <target app> <expected version>
#
# Puts the new app where the target is, only when the new app is signed and its executable reports
# the expected version (the one the build was made from). The old copy waits in a temporary folder,
# outside the Applications folder so macOS never sees two copies of the app, and is deleted only
# after the new one is in place and checked. On any failure, or when the script is stopped (Ctrl-C,
# TERM, HUP) while the old copy is out of the way, the old copy goes back where it was and the
# function fails with a message that says why. The caller has already quit the app.

# What the rollback works on (a trap sees no locals). REPLACE_APP_TARGET is empty when there is
# nothing to roll back. REPLACE_APP_COPYING is 1 once the old copy is out of the way and the target
# holds only what this function copied there.
REPLACE_APP_TARGET=""
REPLACE_APP_OLD=""
REPLACE_APP_OLD_DIR=""
REPLACE_APP_COPYING=0
REPLACE_APP_PREVIOUS_TRAPS=""

# check_app <app> <expected version>: the signature holds and the executable reports the version.
check_app() {
    local app="$1"
    local expected="$2"
    local reported
    if [ -z "$expected" ]; then
        echo "No expected version for $app (the build's version is unknown)" >&2
        return 1
    fi
    if ! codesign --verify "$app" >/dev/null 2>&1; then
        echo "$app failed the signature check (codesign --verify)" >&2
        return 1
    fi
    reported=$("$app/Contents/MacOS/$APP_NAME" --version 2>/dev/null || true)
    if [ "$reported" != "$expected" ]; then
        echo "$app reports version \"$reported\", expected \"$expected\"" >&2
        return 1
    fi
}

# The caller's INT/TERM/HUP traps, as they were before replace_app.
put_back_caller_traps() {
    trap - INT TERM HUP
    eval "$REPLACE_APP_PREVIOUS_TRAPS"
}

# Puts the old copy back where it was. Runs once: it clears what it works on first, so a second
# call (a stop right after a failure) does nothing. The caller ignores INT/TERM/HUP around it.
# Fails when the old copy could not go back; it then stays in the temporary folder and the message
# says where.
restore_old_app() {
    local target="$REPLACE_APP_TARGET"
    local old="$REPLACE_APP_OLD"
    local old_dir="$REPLACE_APP_OLD_DIR"
    local copying="$REPLACE_APP_COPYING"
    REPLACE_APP_TARGET=""
    REPLACE_APP_OLD=""
    REPLACE_APP_OLD_DIR=""
    REPLACE_APP_COPYING=0
    if [ -z "$target" ]; then
        return 0
    fi
    if [ "$copying" = 1 ]; then
        # The target holds only what was copied there: it goes.
        rm -rf "$target"
        if [ -e "$target" ] || [ -L "$target" ]; then
            echo "Could not remove the half copy at $target." >&2
            if [ -n "$old" ]; then
                echo "The old copy is in $old" >&2
            fi
            return 1
        fi
    elif [ -e "$target" ] || [ -L "$target" ]; then
        # Stopped while the old copy was being moved and the target is still there: it stays.
        echo "$target stays as it was." >&2
        if [ -e "$old" ] || [ -L "$old" ]; then
            echo "What was moved is kept in $old" >&2
        fi
        return 1
    fi
    # A first install had no old copy to put back.
    if [ -z "$old" ]; then
        return 0
    fi
    if ! mv "$old" "$target"; then
        echo "The old copy could not be put back: it is in $old" >&2
        return 1
    fi
    rmdir "$old_dir" 2>/dev/null || true
    echo "The old copy is back at $target." >&2
}

# The script was stopped while the old copy was out of the way: put it back, then stop as asked.
replace_app_interrupted() {
    trap '' INT TERM HUP
    if [ -n "$REPLACE_APP_TARGET" ]; then
        echo "Stopped while $REPLACE_APP_TARGET was being replaced." >&2
    fi
    restore_old_app || true
    exit "$1"
}

replace_app() {
    local new_app="$1"
    local target_app="$2"
    local expected="$3"
    local old_dir=""
    local old_app=""
    if ! check_app "$new_app" "$expected"; then
        echo "The new build was not installed; $target_app stays as it was." >&2
        return 1
    fi
    # From the move out of the way until the copy is checked, a stop puts the old copy back.
    REPLACE_APP_PREVIOUS_TRAPS="$(trap -p INT TERM HUP)"
    REPLACE_APP_TARGET="$target_app"
    REPLACE_APP_OLD=""
    REPLACE_APP_OLD_DIR=""
    REPLACE_APP_COPYING=0
    trap 'replace_app_interrupted 130' INT
    trap 'replace_app_interrupted 143' TERM
    trap 'replace_app_interrupted 129' HUP
    # The old copy moves out of the way first; without one (a first install) there is nothing to move.
    if [ -e "$target_app" ] || [ -L "$target_app" ]; then
        # A full template: macOS mktemp -t ignores TMPDIR.
        if ! old_dir="$(mktemp -d "${TMPDIR:-/tmp}/$APP_SLUG-old.XXXXXX")"; then
            REPLACE_APP_TARGET=""
            put_back_caller_traps
            echo "Could not make a temporary folder for the old copy; $target_app stays as it was." >&2
            return 1
        fi
        old_app="$old_dir/$(basename "$target_app")"
        REPLACE_APP_OLD="$old_app"
        REPLACE_APP_OLD_DIR="$old_dir"
        if ! mv "$target_app" "$old_app"; then
            trap '' INT TERM HUP
            REPLACE_APP_TARGET=""
            echo "Could not move $target_app out of the way (is its folder writable?)." >&2
            if [ -e "$target_app" ] || [ -L "$target_app" ]; then
                echo "$target_app stays as it was." >&2
            fi
            # Across volumes mv copies, then deletes: what it got to may be the only full copy.
            if [ -e "$old_app" ] || [ -L "$old_app" ]; then
                echo "What was moved is kept in $old_app" >&2
            else
                rmdir "$old_dir" 2>/dev/null || true
            fi
            put_back_caller_traps
            return 1
        fi
    fi
    REPLACE_APP_COPYING=1
    if cp -R "$new_app" "$target_app" && check_app "$target_app" "$expected"; then
        # In place and checked: nothing to roll back any more.
        REPLACE_APP_TARGET=""
        put_back_caller_traps
        if [ -n "$old_dir" ]; then
            rm -rf "$old_dir"
        fi
        return 0
    fi
    # Half a copy, or one that does not check out: it goes, and the old copy comes back. A stop
    # now would only get in the way of that, so it waits.
    trap '' INT TERM HUP
    echo "Could not copy $new_app to $target_app." >&2
    restore_old_app || true
    put_back_caller_traps
    return 1
}
