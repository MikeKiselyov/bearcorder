#!/bin/bash
# Pulls the latest source, rebuilds Bugbear and replaces the running copy.
# The app runs this from its "Update" button; it also works by hand:
#
#   scripts/update.sh ["/Applications/Bugbear.app"]
#
# Without an argument the app is installed like scripts/build-app.sh --install.
set -euo pipefail

cd "$(dirname "$0")/.."
TARGET_APP="${1:-}"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "This folder has local changes, so it was not updated automatically:" >&2
    git status --short --untracked-files=no >&2
    echo "Commit or stash them, then run scripts/update.sh again." >&2
    exit 2
fi

echo "==> git pull"
git pull --ff-only

if [ -z "$TARGET_APP" ]; then
    scripts/build-app.sh --install
    exit 0
fi

echo "==> build"
scripts/build-app.sh

# Running straight from this folder's build/: the fresh build is already in place.
if [ "$TARGET_APP" = "$(pwd)/build/Bugbear.app" ]; then
    pkill -x Bugbear 2>/dev/null || true
    sleep 1
    open "$TARGET_APP"
    echo "==> updated"
    exit 0
fi

echo "==> replacing $TARGET_APP"
pkill -x Bugbear 2>/dev/null || true
sleep 1
rm -rf "$TARGET_APP"
cp -R "build/Bugbear.app" "$TARGET_APP"
open "$TARGET_APP"
echo "==> updated"
