# shellcheck shell=bash
# Sourced by the scripts: the app's name, read from Sources/AppCore/Support/AppInfo.swift so the name
# lives in one place, and what follows from it the same way as in AppInfo.
#   APP_NAME           the name people see, also the executable and process, and the folders on disk
#                      (Application Support, Logs, the default save folder)
#   APP_SLUG           the name in lower case with "-" for spaces
#   DEFAULT_BUNDLE_ID  the bundle id of copies built without APP_BUNDLE_ID (the installer's)
APP_NAME=$(sed -n 's/.*static let name = "\(.*\)"$/\1/p' "$(dirname "${BASH_SOURCE[0]}")/../../Sources/AppCore/Support/AppInfo.swift")
if [ -z "$APP_NAME" ]; then
    echo "scripts/lib/app-name.sh: no name in Sources/AppCore/Support/AppInfo.swift" >&2
    exit 1
fi
APP_SLUG=$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
# Used by the scripts that source this file.
# shellcheck disable=SC2034
DEFAULT_BUNDLE_ID="io.github.$APP_SLUG.app"
