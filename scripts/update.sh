#!/bin/bash
# Pulls the latest source, rebuilds the app and replaces the running copy.
# The app runs this from its "Update" button; it also works by hand:
#
#   scripts/update.sh ["/Applications/<name>.app"]
#
# Without an argument the app is installed like scripts/build-app.sh --install.
set -euo pipefail

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

cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source scripts/lib/app-name.sh
TARGET_APP="${1:-}"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "This folder has local changes, so it was not updated automatically:" >&2
    git status --short --untracked-files=no >&2
    echo "Commit or stash them, then run scripts/update.sh again." >&2
    exit 2
fi

# Updates always come from main, also for a copy built from a pull request branch.
echo "==> git fetch"
git fetch origin main
branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" != "main" ]; then
    # A branch with work that is not on main yet stays as it is.
    if [ -n "$(git rev-list HEAD --not origin/main)" ]; then
        echo "The branch $branch has commits that are not on main, so it was not switched to main:" >&2
        git log --oneline HEAD --not origin/main >&2
        echo "Merge or switch the branch yourself, then run scripts/update.sh again." >&2
        exit 3
    fi
    echo "==> switching to main"
    git checkout main
fi
echo "==> updating main"
git merge --ff-only origin/main

if [ -z "$TARGET_APP" ]; then
    scripts/build-app.sh --install
    exit 0
fi

echo "==> build"
scripts/build-app.sh

# Running straight from this folder's build/: the fresh build is already in place. -ef compares the
# folder itself, so another spelling of its path (a symlink, /tmp or /private/tmp) never deletes it.
if [ "$TARGET_APP" -ef "build/$APP_NAME.app" ]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    wait_for_app_to_quit
    open "$TARGET_APP"
    echo "==> updated"
    exit 0
fi

# Only a copy of this app is replaced, by the same rule as build-app.sh --install; another app stays.
# shellcheck source=lib/permissions.sh
source scripts/lib/permissions.sh
built_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "build/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || true)
if { [ -e "$TARGET_APP" ] || [ -L "$TARGET_APP" ]; } && ! is_our_app "$TARGET_APP" "$built_id"; then
    echo "$TARGET_APP is not a $APP_NAME build (its executable, bundle id or build keys differ), so it was not replaced." >&2
    echo "Move it away, then run scripts/update.sh again." >&2
    exit 4
fi

echo "==> replacing $TARGET_APP"
pkill -x "$APP_NAME" 2>/dev/null || true
wait_for_app_to_quit
rm -rf "$TARGET_APP"
cp -R "build/$APP_NAME.app" "$TARGET_APP"
open "$TARGET_APP"
echo "==> updated"
