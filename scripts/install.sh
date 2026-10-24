#!/bin/bash
# One-command install: gets the source, builds Bugbear on this Mac and puts it in Applications.
# Run it again any time to update.
#
#   curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bugbear-app/main/scripts/install.sh | bash
#
# Options (environment variables):
#   BUGBEAR_REPO        git URL to install from (default: the main GitHub repository)
#   BUGBEAR_SOURCE_DIR  where the source is kept (default: ~/.bugbear)
#   NO_COLOR            plain text, no colors or animation
set -euo pipefail

REPO_URL="${BUGBEAR_REPO:-https://github.com/MikeKiselyov/bugbear-app.git}"
SOURCE_DIR="${BUGBEAR_SOURCE_DIR:-$HOME/.bugbear}"

# Colors and the spinner only in a real terminal.
FANCY=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    FANCY=1
fi
H=""; B=""; C=""; N=""; BOLD=""; DIM=""; OK=""; BAD=""
if [ "$FANCY" = "1" ]; then
    H=$'\033[97m'          # the bear
    B=$'\033[38;5;216m'    # the bun
    C=$'\033[38;5;203m'    # the bug, and the accent
    N=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    OK=$'\033[38;5;114m'
    BAD=$'\033[38;5;203m'
fi

logo() {
    local lines=(
# logo-start
    "     ${H}▄██████▄▄${N}     ${H}▄▄▄▄▄${N}     ${H}▄██████▄▄${N}"
    "    ${H}██████████████████████████████████▄${N}"
    "   ${H}████████████████████████████████████${N}"
    "   ${H}████████████████████████████████████${N}"
    "    ${H}▀█████████████████████████████████▀${N}"
    "      ${H}████████▀${N}  ${H}▀███████▀${N}  ${H}▀████████${N}"
    "      ${H}████████${N}   ${H}▄███████▄${N}  ${H}▄█████▀▀█${N}"
    "      ${H}████████████████████████████▄${N}${C}█${N}"
    "      ${H}█████████████▀${N}   ${H}▀██████▀▀██▀${N}${C}▄█▄▄▄▄${N}"
    "      ${H}▀████████▀▀▀▀${N}    ${H}▀▀▀▀▀██${N}${C}▀█${N}${H}▀${N} ${C}████${N}"
    "       ${H}▀▀▀${N}   ${B}▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄${N} ${C}▄▄██████${N}"
    "       ${B}▄▄██████████████████▀▀${N} ${C}█████▄███▀${N}"
    "    ${B}▄█████████████▄███████▄${N}${C}▀▀▀▀▄▀████▄▄${N}"
    "   ${B}███████████████████████████▄${N} ${C}▀▀▀█${N} ${B}▄${N}${C}█${N}${B}▄${N}"
    "   ${B}██████████████████▀█████████████${N}${C}▀▀${N}${B}███${N}"
    "   ${B}▀███████████▄██████████████████████▀${N}"
    "     ${B}▀▀█████████████████████████████▀${N}"
    "         ${B}▀▀▀▀█████████████████▀▀▀${N}"
# logo-end
    )
    echo
    for line in "${lines[@]}"; do
        printf '%s\n' "$line"
    done
    echo
    printf '   %sBug%sbear%s\n' "$BOLD$H" "$C" "$N"
    printf '   %sScreenshots, recordings and a dev toolbox%s\n' "$DIM" "$N"
    printf '   %sfor people who build and test software.%s\n' "$DIM" "$N"
    echo
}

# A step: "•  Checking your Mac…", then the same line becomes "✓  macOS 15.1".
# Without a terminal only the finished line is printed, so plain output reads the same.
step() {
    if [ "$FANCY" = "1" ]; then
        printf '   %s•%s  %s…' "$DIM" "$N" "$1"
    fi
}
done_step() {
    if [ "$FANCY" = "1" ]; then
        printf '\r\033[K'
    fi
    printf '   %s✓%s  %s\n' "$OK" "$N" "$1"
}
stop() {
    if [ "$FANCY" = "1" ]; then
        printf '\r\033[K'
    fi
    printf '   %s✗  %s%s\n' "$BAD" "$1" "$N" >&2
    exit 1
}

# Runs a command with its output in a log file, showing a spinner, the time and a few friendly lines.
TIPS=(
    "The first build takes a couple of minutes. Good moment for a cup of tea ☕"
    "Bugbear keeps the last minutes of your screen, so a bug cannot hide."
    "⌥⇧1 saves the last 30 seconds. ⌥⇧M marks the moment the bug happened."
    "⌥⇧4 screenshots an area, ⌥⇧D opens the dev toolbox with your clipboard."
    "Everything stays on your Mac. Nothing is uploaded anywhere."
    "Built right here on your Mac, from the source you just downloaded."
)
with_spinner() {
    local label="$1" log="$2"
    shift 2
    if [ "$FANCY" != "1" ]; then
        printf '   …  %s\n' "$label"
        printf '      %s\n' "${TIPS[0]}"
        "$@" >"$log" 2>&1
        return
    fi
    "$@" >"$log" 2>&1 &
    local pid=$!
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local start=$SECONDS tick=0
    printf '\033[?25l'
    # Give the cursor back even if the install is stopped with Ctrl-C.
    trap 'printf "\033[?25h"' EXIT
    trap 'printf "\033[?25h\n"; exit 130' INT TERM
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$((SECONDS - start))
        local tip="${TIPS[$(( (elapsed / 8) % ${#TIPS[@]} ))]}"
        printf '\r\033[K   %s%s%s  %s %s%d:%02d%s\n\033[K      %s%s%s\033[1A' \
            "$C" "${frames[$((tick % ${#frames[@]}))]}" "$N" "$label" "$DIM" $((elapsed / 60)) $((elapsed % 60)) "$N" "$DIM" "$tip" "$N"
        tick=$((tick + 1))
        sleep 0.1
    done
    printf '\033[?25h\r\033[K\n\033[K\033[1A'
    wait "$pid"
}

logo

step "Checking your Mac"
macos_version="$(sw_vers -productVersion)"
macos_major="$(echo "$macos_version" | cut -d. -f1)"
if [ "$macos_major" -lt 14 ]; then
    stop "Bugbear needs macOS 14 Sonoma or later (this Mac has $macos_version)."
fi
done_step "macOS $macos_version"

step "Checking developer tools"
if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install 2>/dev/null || true
    stop "Installing Apple's Command Line Tools: finish the dialog that just opened, then run this command again."
fi
swift_version="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9.]+).*/\1/p' | head -1)"
swift_major="$(echo "$swift_version" | cut -d. -f1)"
if [ -z "$swift_major" ] || [ "$swift_major" -lt 6 ]; then
    stop "Swift 6 or later is needed (found: ${swift_version:-none}). Update Xcode or the Command Line Tools in Software Update."
fi
done_step "Swift $swift_version"

if [ -d "$SOURCE_DIR/.git" ]; then
    step "Getting the latest source"
    git -C "$SOURCE_DIR" pull --ff-only --quiet || stop "Could not update the source in $SOURCE_DIR."
    done_step "Source is up to date ($(git -C "$SOURCE_DIR" rev-parse --short HEAD))"
else
    step "Downloading the source"
    git clone --quiet "$REPO_URL" "$SOURCE_DIR" || stop "Could not download $REPO_URL."
    done_step "Source downloaded to ${SOURCE_DIR/#$HOME/~}"
fi

LOG="$SOURCE_DIR/build/install.log"
mkdir -p "$SOURCE_DIR/build"
if ! with_spinner "Building Bugbear" "$LOG" "$SOURCE_DIR/scripts/build-app.sh" --install; then
    printf '   %s✗  The build failed.%s The end of the log (%s):\n\n' "$BAD" "$N" "${LOG/#$HOME/~}" >&2
    tail -20 "$LOG" | sed 's/^/      /' >&2
    exit 1
fi
done_step "Built and signed ($(grep -q "ad-hoc" "$LOG" && echo "ad-hoc: macOS asks for permissions again after updates" || echo "Apple Development certificate"))"
installed="$(sed -n 's/^==> installed to //p' "$LOG" | tail -1)"
done_step "Installed to ${installed:-Applications}"

echo
printf '   %s✨ All set!%s Look for the bear in the menu bar, top right.\n' "$BOLD" "$N"
printf '   %sA short guide opens on first launch.%s\n' "$DIM" "$N"
echo
printf '   %s⌥⇧1%s  save the last 30 seconds\n' "$C" "$N"
printf '   %s⌥⇧4%s  screenshot an area\n' "$C" "$N"
printf '   %s⌥⇧D%s  dev toolbox\n' "$C" "$N"
echo
printf '   %sRun this command again any time to update. Happy bug hunting! 🐻%s\n' "$DIM" "$N"
echo
