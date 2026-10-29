#!/bin/bash
# Pulls the latest source, rebuilds Bugbear and replaces the running copy.
# The app runs this from its "Update" button; it also works by hand:
#
#   scripts/update.sh ["/Applications/Bugbear.app"]
#
# Without an argument the app is installed like scripts/build-app.sh --install.
set -euo pipefail

# Bugbear stops its screen capture before it quits (up to 2 s), so wait for it to be gone.
wait_for_bugbear_to_quit() {
    local tries=0
    while pgrep -x Bugbear >/dev/null 2>&1 && [ "$tries" -lt 50 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    # Still there (stuck in a modal alert): it must not keep running from a replaced app.
    if pgrep -x Bugbear >/dev/null 2>&1; then
        pkill -9 -x Bugbear 2>/dev/null || true
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

# Running straight from this folder's build/: the fresh build is already in place.
if [ "$TARGET_APP" = "$(pwd)/build/$APP_NAME.app" ]; then
    pkill -x Bugbear 2>/dev/null || true
    wait_for_bugbear_to_quit
    open "$TARGET_APP"
    echo "==> updated"
    exit 0
fi

echo "==> replacing $TARGET_APP"
pkill -x Bugbear 2>/dev/null || true
wait_for_bugbear_to_quit
rm -rf "$TARGET_APP"
cp -R "build/$APP_NAME.app" "$TARGET_APP"
open "$TARGET_APP"
echo "==> updated"
