# shellcheck shell=bash
# Sourced by build-app.sh --install.
#
# An installed copy with another bundle id (the installer's io.github.bugbear.app and a build with
# BUGBEAR_BUNDLE_ID from .env) leaves its permission records behind when it is replaced, and System
# Settings then lists two Bugbears: one switched on that is gone, one switched off that asks.
#
#   is_earlier_bugbear <app> <bundle id being installed>   prints the app's id when it is a Bugbear
#                                                          with another id, fails otherwise
#   forget_permissions <old bundle id> <copy of the old app>
#
# The user's records go with tccutil, the copy registered around it as the old app is already gone. Screen Recording and Accessibility live in the system's
# records, which need root: macOS asks for the password once. tccutil only takes ids LaunchServices
# knows, and root has a registry of its own, so the old copy is registered inside the same call.
# BUGBEAR_KEEP_PERMISSIONS=1 leaves the system's records alone (no password dialog).
# The id comes from the old copy's Info.plist, so only a plain reverse-DNS id goes on to root.

LSREGISTER="${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

is_earlier_bugbear() {
    local plist="$1/Contents/Info.plist"
    local app_id
    local executable
    app_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)
    executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null || true)
    # Another app under this name keeps its permissions.
    if [ -z "$app_id" ] || [ "$app_id" = "$2" ] || [ "$executable" != Bugbear ]; then
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
    if [ -n "${BUGBEAR_KEEP_PERMISSIONS:-}" ]; then
        return 0
    fi
    echo "==> removing the permissions of the replaced $old_id (macOS asks for your password)"
    # The paths go in as arguments and AppleScript quotes them, so no name can break the command.
    if ! osascript - "$LSREGISTER" "$copy" "$old_id" >/dev/null 2>&1 <<'APPLESCRIPT'
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
