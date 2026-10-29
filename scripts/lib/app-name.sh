# shellcheck shell=bash
# Sourced by the scripts: APP_NAME, the name people see (the .app, its Info.plist, messages), read
# from Sources/BugbearCore/Support/AppInfo.swift so the name lives in one place.
# The executable and process stay "Bugbear" whatever the name: scripts find and quit older copies
# by it, and folders with people's captures and logs keep their names (AppInfo.storageName).
APP_NAME=$(sed -n 's/.*static let name = "\(.*\)"$/\1/p' "$(dirname "${BASH_SOURCE[0]}")/../../Sources/BugbearCore/Support/AppInfo.swift")
if [ -z "$APP_NAME" ]; then
    echo "scripts/lib/app-name.sh: no name in Sources/BugbearCore/Support/AppInfo.swift" >&2
    exit 1
fi
