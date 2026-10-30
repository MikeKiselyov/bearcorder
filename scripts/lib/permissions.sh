# shellcheck shell=bash
# Sourced by build-app.sh --install and update.sh, after scripts/lib/app-name.sh (APP_NAME,
# DEFAULT_BUNDLE_ID).
#
# An installed copy with another bundle id (the installer's DEFAULT_BUNDLE_ID and a build with
# APP_BUNDLE_ID from .env) leaves its permission records behind when it is replaced, and System
# Settings then lists the app twice: one switched on that is gone, one switched off that asks.
#
#   is_our_app <app> <bundle id being installed>           succeeds when the app is a copy of this one
#   is_our_earlier_app <app> <bundle id being installed>   prints the app's id when it is a copy of this
#                                                          one with another id, fails otherwise
#   forget_permissions <old bundle id> <copy of the old app>
#
# The user's records go with tccutil, the copy registered around it as the old app is already gone. Screen Recording and Accessibility live in the system's
# records, which need root: macOS asks for the password once. tccutil only takes ids LaunchServices
# knows, and root has a registry of its own, so the old copy is registered inside the same call.
# APP_KEEP_PERMISSIONS=1 leaves the system's records alone (no password dialog).
# The id comes from the old copy's Info.plist, so only a plain reverse-DNS id goes on to root.

SYSTEM_LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# LSREGISTER (tests) replaces it only for the user's part; root always runs the system's one.
LSREGISTER="${LSREGISTER:-$SYSTEM_LSREGISTER}"

# A copy of this app: its executable is APP_NAME, and it has the keys every build-app.sh build writes
# or one of the app's bundle ids (the one being installed, the installer's).
is_our_app() {
    local plist="$1/Contents/Info.plist"
    local app_id
    local executable
    app_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)
    executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null || true)
    if [ "$executable" != "$APP_NAME" ]; then
        return 1
    fi
    if [ -n "$app_id" ] && { [ "$app_id" = "$2" ] || [ "$app_id" = "$DEFAULT_BUNDLE_ID" ]; }; then
        return 0
    fi
    if /usr/libexec/PlistBuddy -c "Print :SourcePath" "$plist" >/dev/null 2>&1; then
        return 0
    fi
    if /usr/libexec/PlistBuddy -c "Print :SourceCommit" "$plist" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

is_our_earlier_app() {
    local app_id
    app_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true)
    # Another app under this name keeps its permissions.
    if [ -z "$app_id" ] || [ "$app_id" = "$2" ] || ! is_our_app "$1" "$2"; then
        return 1
    fi
    echo "$app_id"
}

forget_permissions() {
    local old_id="$1"
    local copy="$2"
    if ! [[ "$old_id" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
        echo "==> skipped: unexpected bundle id \"$old_id\", its permissions stay"
        return 0
    fi
    "$LSREGISTER" -f "$copy" >/dev/null 2>&1 || true
    tccutil reset All "$old_id" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$copy" >/dev/null 2>&1 || true
    if [ -n "${APP_KEEP_PERMISSIONS:-}" ]; then
        return 0
    fi
    echo "==> removing the permissions of the replaced $old_id (macOS asks for your password)"
    # The paths go in as arguments and AppleScript quotes them, so no name can break the command.
    if ! osascript - "$SYSTEM_LSREGISTER" "$copy" "$old_id" >/dev/null 2>&1 <<'APPLESCRIPT'
on run arguments
    set lsregister to quoted form of item 1 of arguments
    set kept to quoted form of item 2 of arguments
    set oldId to quoted form of item 3 of arguments
    do shell script lsregister & " -f " & kept & "; tccutil reset All " & oldId & "; " & lsregister & " -u " & kept with administrator privileges
end run
APPLESCRIPT
    then
        echo "    not removed: if System Settings lists $APP_NAME twice, select the old one and press -"
    fi
    return 0
}
