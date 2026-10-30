#!/bin/bash
# Sends an automation command to the running app (needs automationEnabled, see Automation.swift).
#   scripts/dev/app-command.sh save:10
# The command goes in as an argument, not inside the script text, so quotes and backslashes in it
# arrive as they are.
# A small compiled sender (app-send.swift) does the posting: much faster than starting osascript
# for every command. It is built on first use and again when the source is newer. When swiftc fails,
# the old osascript line sends the command.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$root/scripts/lib/app-name.sh"
# The name Automation.notificationName listens for.
notification="$APP_NAME.automation"
source_file="$root/scripts/dev/app-send.swift"
sender="$root/.build/app-send"
if [ ! -x "$sender" ] || [ "$source_file" -nt "$sender" ]; then
    mkdir -p "$root/.build"
    # Built under a name of its own and then moved, so two scripts starting together do not run a half-written file.
    partial="$sender.$$"
    if swiftc -O "$source_file" -o "$partial" >/dev/null 2>&1; then
        mv -f "$partial" "$sender"
    else
        rm -f "$partial"
    fi
fi
if [ -x "$sender" ]; then
    exec "$sender" "$notification" "$1"
fi
# The $ in the script is JavaScript (ObjC bridge), not the shell's.
# shellcheck disable=SC2016
osascript -l JavaScript -e 'function run(argv) { ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(argv[0], argv[1], $(), true); }' "$notification" "$1" >/dev/null
