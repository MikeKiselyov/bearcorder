#!/bin/bash
# One-command install: gets the source, builds Bugbear on this Mac and puts it in Applications.
# Run it again any time to update.
#
#   curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bugbear-app/main/scripts/install.sh | bash
#
# Options (environment variables):
#   BUGBEAR_REPO        git URL to install from (default: the main GitHub repository)
#   BUGBEAR_SOURCE_DIR  where the source is kept (default: ~/.bugbear)
set -euo pipefail

REPO_URL="${BUGBEAR_REPO:-https://github.com/MikeKiselyov/bugbear-app.git}"
SOURCE_DIR="${BUGBEAR_SOURCE_DIR:-$HOME/.bugbear}"

say() { printf '\033[1m==> %s\033[0m\n' "$1"; }
stop() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

say "Checking macOS"
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$macos_major" -lt 14 ]; then
    stop "Bugbear needs macOS 14 Sonoma or later (this Mac has $(sw_vers -productVersion))."
fi

say "Checking developer tools"
if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install 2>/dev/null || true
    stop "Installing Apple's Command Line Tools: finish the dialog that just opened, then run this command again."
fi
swift_major="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -1)"
if [ -z "$swift_major" ] || [ "$swift_major" -lt 6 ]; then
    stop "Swift 6 or later is needed (found: ${swift_major:-none}). Update Xcode or the Command Line Tools in Software Update."
fi

if [ -d "$SOURCE_DIR/.git" ]; then
    say "Updating the source in $SOURCE_DIR"
    git -C "$SOURCE_DIR" pull --ff-only
else
    say "Downloading the source to $SOURCE_DIR"
    git clone "$REPO_URL" "$SOURCE_DIR"
fi

say "Building (the first build takes a few minutes)"
"$SOURCE_DIR/scripts/build-app.sh" --install

say "Done. Bugbear is in the menu bar (the bear icon)."
