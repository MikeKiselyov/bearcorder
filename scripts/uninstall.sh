#!/bin/bash
# One-command uninstall: removes Bugbear from this Mac - the app, captures, the screen buffer, logs,
# settings, permissions, the signing certificate and the source kept for updates. Files you saved
# or exported stay where you put them.
#
#   curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bugbear-app/main/scripts/uninstall.sh | bash
#   scripts/uninstall.sh --yes    # from a clone, without asking first
#
# Options (environment variables):
#   BUGBEAR_SOURCE_DIR       where the installer kept the source (default: ~/.bugbear)
#   BUGBEAR_APPS_DIRS        folders to look for the app in, ":" between them
#                            (default: /Applications and ~/Applications)
#   BUGBEAR_DRY_SYSTEM       1: print the steps that touch the running app, settings, permissions
#                            and keychains instead of doing them (for tests)
#   BUGBEAR_TTY              where the answers come from (default: /dev/tty; a file in tests)
#   NO_COLOR                 plain text
set -euo pipefail

# The name people see and the folders' name. This file can run without the source, so it keeps its
# own copies; a unit test checks they match AppInfo.name and AppInfo.storageName.
APP_NAME="Bugbear"
STORAGE_NAME="Bugbear"
# The executable keeps this name whatever the app is called.
EXECUTABLE="Bugbear"
# The bundle id of copies built by the installer.
DEFAULT_BUNDLE_ID="io.github.bugbear.app"
# Where people say why they left (.github/ISSUE_TEMPLATE/uninstall_feedback.yml); a unit test
# checks the repository matches the app's.
FEEDBACK_URL="https://github.com/MikeKiselyov/bugbear-app/issues/new?template=uninstall_feedback.yml"

SOURCE_DIR="${BUGBEAR_SOURCE_DIR:-$HOME/.bugbear}"
APPS_DIRS="${BUGBEAR_APPS_DIRS:-/Applications:$HOME/Applications}"
DRY_SYSTEM="${BUGBEAR_DRY_SYSTEM:-}"
TTY="${BUGBEAR_TTY:-/dev/tty}"
SUPPORT_DIR="$HOME/Library/Application Support/$STORAGE_NAME"
LOGS_DIR="$HOME/Library/Logs/$STORAGE_NAME"
KEYCHAIN="$SUPPORT_DIR/Signing/bugbear-signing.keychain-db"

ASK=1
for argument in "$@"; do
    case "$argument" in
        --yes|-y) ASK=0 ;;
        *)
            echo "usage: scripts/uninstall.sh [--yes]" >&2
            exit 2
            ;;
    esac
done

OK=""; DIM=""; BOLD=""; N=""; H=""; C=""; T=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    OK=$'\033[38;5;114m'
    DIM=$'\033[2m'
    BOLD=$'\033[1m'
    N=$'\033[0m'
    H=$'\033[97m'          # the bear and the magnifying glass, as in install.sh
    C=$'\033[38;5;203m'    # the bug
    T=$'\033[38;5;75m'     # tears
fi

# The installer's bear, crying: it is sad to see you go.
crying_bear() {
    local lines=(
    "      ${H}▄▄██▄▄${N}     ${H}▄${N}     ${H}▄▄██▄▄${N}"
    "     ${H}▄████████████████████████▄${N}"
    "     ${H}██████████████████████████${N}"
    "     ${H}▀████████████████████████${N}"
    "       ${H}██████▀${N} ${H}▀█████▀${N} ${H}▀█████${N}"
    "       ${H}██████▄▄▄█████▄▄▄█████${N}"
    "       ${H}███████${N}${T}█${N}${H}█▀${N}  ${H}███${N}${T}█${N}${H}██▀▀▀${N}"
    "       ${H}▀██████${N}${T}█${N}${H}███████${N}${T}█${N} ${H}▄▄████████▄▄${N}"
    "        ${H}▀█████${N}${T}█${N}${H}██████${N} ${T}▀${N}${H}██▀${N}        ${H}▀██▄${N}"
    "          ${H}▀▀██${N}${T}█${N}${H}█████${N} ${H}▄█▀${N}   ${C}▀▄${N}   ${C}▄▀${N}  ${H}▀██${N}"
    "              ${H}▀▀▀▀▀${N}  ${H}██${N}      ${C}███${N}      ${H}██${N}"
    "              ${T}▄${N}     ${H}██${N}   ${C}▀▄███▀███▄▀${N}  ${H}██${N}"
    "                    ${H}▀█${N}   ${C}▄${N} ${C}███${N} ${C}███${N} ${C}▄${N}  ${H}██${N}"
    "             ${T}•${N}       ${H}██${N}   ${C}▀███${N} ${C}███▀${N}  ${H}▄█▀${N}"
    "                      ${H}██▄${N}   ${C}▀▀${N} ${C}▀▀${N}   ${H}▄█▀${N}"
    "                       ${H}▀██▄▄▄${N}   ${H}▄▄██▀${N} ${H}▄█▄${N}"
    "                          ${H}▀▀▀██▀▀▀▀${N}  ${H}█████▄${N}"
    "                                      ${H}▀█████▄${N}"
    "                                        ${H}▀████${N}"
    "                                          ${H}▀▀${N}"
    )
    echo
    for line in "${lines[@]}"; do
        printf '%s\n' "$line"
    done
    echo
}

done_step() { echo "${OK}✓${N}  $1"; }

# A step that touches the running app or the system; only printed in a test run. Printed to the
# terminal's own copy of stdout (3), so a step's own output can be hidden without hiding this.
exec 3>&1
system() {
    if [ "$DRY_SYSTEM" = "1" ]; then
        echo "would run: $*" >&3
        return 0
    fi
    "$@"
}

# Every installed copy, whatever it is called: its executable is Bugbear.
apps=()
IFS=':' read -r -a app_folders <<< "$APPS_DIRS"
for folder in "${app_folders[@]}"; do
    for app in "$folder"/*.app; do
        if [ ! -f "$app/Contents/Info.plist" ]; then
            continue
        fi
        executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Contents/Info.plist" 2>/dev/null || true)
        if [ "$executable" = "$EXECUTABLE" ]; then
            apps+=("$app")
        fi
    done
done

# Settings are kept by bundle id: the installer's, every installed copy's, and a clone's own (.env).
bundle_ids=("$DEFAULT_BUNDLE_ID")
for app in "${apps[@]+"${apps[@]}"}"; do
    app_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null || true)
    if [ -n "$app_id" ] && [[ " ${bundle_ids[*]} " != *" $app_id "* ]]; then
        bundle_ids+=("$app_id")
    fi
done
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$script_dir" ] && [ -f "$script_dir/../.env" ]; then
    clone_id=$(sed -n 's/^BUGBEAR_BUNDLE_ID=//p' "$script_dir/../.env" | tr -d '"' | head -1)
    if [ -n "$clone_id" ] && [[ " ${bundle_ids[*]} " != *" $clone_id "* ]]; then
        bundle_ids+=("$clone_id")
    fi
fi

# Where exports went, to say they stay.
exports_dir="$HOME/Desktop/$STORAGE_NAME"
for bundle_id in "${bundle_ids[@]}"; do
    chosen=$(defaults read "$bundle_id" outputFolderPath 2>/dev/null || true)
    if [ -n "$chosen" ]; then
        exports_dir="$chosen"
    fi
done

crying_bear
echo "   ${BOLD}Oh no, you are leaving?${N} The bear is already crying."
echo "   ${DIM}It will be brave. Here is what goes:${N}"
echo
echo "This removes:"
if [ ${#apps[@]} -eq 0 ]; then
    echo "  - the app ${DIM}(not found in $APPS_DIRS)${N}"
fi
for app in "${apps[@]+"${apps[@]}"}"; do
    echo "  - $app"
done
for folder in "$SUPPORT_DIR" "$LOGS_DIR" "$SOURCE_DIR"; do
    if [ -e "$folder" ]; then
        size=$(du -sh "$folder" 2>/dev/null | cut -f1 | tr -d ' ')
        echo "  - $folder ${DIM}($size)${N}"
    fi
done
echo "  - permissions: Screen Recording, Accessibility, Microphone, Camera"
echo "  - settings, caches, the login item and temporary files"
echo
echo "Your saved files stay in $exports_dir."
echo

if [ "$ASK" = "1" ]; then
    # Piped from curl, stdin is the script: the answer comes from the terminal, if there is one.
    if ! (: < "$TTY") 2>/dev/null; then
        echo "Run it again with --yes to uninstall without asking." >&2
        exit 1
    fi
    printf "Uninstall %s? [y/N] " "$APP_NAME"
    # Opened once, so the answers are read one after another.
    exec 4< "$TTY"
    read -r answer <&4 || answer=""
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ] && [ "$answer" != "yes" ]; then
        echo "Phew! The bear wipes its tears. Nothing was removed. 🐻"
        exit 0
    fi
fi

# Quit first: it stops its screen capture before quitting (up to 2 s), and a running copy would
# write its settings back.
if pgrep -x "$EXECUTABLE" >/dev/null 2>&1 || [ "$DRY_SYSTEM" = "1" ]; then
    system pkill -x "$EXECUTABLE" || true
    tries=0
    while [ "$DRY_SYSTEM" != "1" ] && pgrep -x "$EXECUTABLE" >/dev/null 2>&1 && [ "$tries" -lt 50 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    if [ "$DRY_SYSTEM" != "1" ] && pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
        pkill -9 -x "$EXECUTABLE" 2>/dev/null || true
        sleep 0.5
    fi
    done_step "Quit $APP_NAME"
fi

# The signing certificate's keychain off the search list before its file goes. Deleting the
# keychain does not read it, so no password is asked.
if [ -e "$KEYCHAIN" ]; then
    system security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    done_step "Removed the signing certificate"
fi

# Only the app itself can take itself off the login items, so it is asked to before it goes.
for app in "${apps[@]+"${apps[@]}"}"; do
    system "$app/Contents/MacOS/$EXECUTABLE" --forget-login-item >/dev/null 2>&1 || true
done
if [ ${#apps[@]} -gt 0 ]; then
    done_step "Removed the login item"
fi

# Permissions macOS gave the app; a new install asks again. Before the app goes: tccutil only
# resets a bundle id macOS still knows an app for, and refuses one whose app is gone. A record
# left like that ties the next install to the old id, and Bugbear never shows up in the Screen
# Recording list.
for bundle_id in "${bundle_ids[@]}"; do
    system tccutil reset All "$bundle_id" >/dev/null 2>&1 || true
done
done_step "Removed the permissions"

for app in "${apps[@]+"${apps[@]}"}"; do
    rm -rf "$app"
    done_step "Removed $app"
done

# macOS remembers every copy it has seen. A copy that is gone but still remembered (like the
# installer's build in the source folder) keeps its bundle id tied to the app, and then a new
# install's Screen Recording request is filed under the old id: the app never shows up in the list
# to switch on. So the removed copies and any remembered copy that is gone are forgotten.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
forget_paths=()
for app in "${apps[@]+"${apps[@]}"}"; do
    forget_paths+=("$app")
done
forget_paths+=("$SOURCE_DIR/build/$APP_NAME.app")
if [ -x "$LSREGISTER" ]; then
    while IFS= read -r remembered; do
        if [ ! -e "$remembered" ] && [[ " ${forget_paths[*]} " != *" $remembered "* ]]; then
            forget_paths+=("$remembered")
        fi
    done < <("$LSREGISTER" -dump 2>/dev/null | sed -n "s|^path: *\(.*/$APP_NAME\.app\) (0x[0-9a-f]*)\$|\1|p" | sort -u)
fi
for remembered in "${forget_paths[@]}"; do
    system "$LSREGISTER" -u "$remembered" >/dev/null 2>&1 || true
done
done_step "macOS forgot the removed copies"

for folder in "$SUPPORT_DIR" "$LOGS_DIR"; do
    if [ -e "$folder" ]; then
        rm -rf "$folder"
        done_step "Removed $folder"
    fi
done
if [ -e "$SOURCE_DIR" ]; then
    rm -rf "$SOURCE_DIR"
    done_step "Removed the source kept for updates ($SOURCE_DIR)"
fi

for bundle_id in "${bundle_ids[@]}"; do
    system defaults delete "$bundle_id" >/dev/null 2>&1 || true
    system defaults delete "$bundle_id.tests" >/dev/null 2>&1 || true
    # What macOS keeps per app: the settings files (also after defaults delete), caches, cookies,
    # and windows to restore.
    rm -f "$HOME/Library/Preferences/$bundle_id.plist" "$HOME/Library/Preferences/$bundle_id.tests.plist"
    rm -rf "$HOME/Library/Caches/$bundle_id"
    rm -rf "$HOME/Library/HTTPStorages/$bundle_id" "$HOME/Library/HTTPStorages/$bundle_id.binarycookies"
    rm -rf "$HOME/Library/Saved Application State/$bundle_id.savedState"
    rm -rf "$HOME/Library/WebKit/$bundle_id"
done
# Settings files of builds run from the source and of its checks: "Bugbear.plist" from a build
# without a bundle id, and scratch settings of the self-test and the automation checks.
rm -f "$HOME/Library/Preferences/$EXECUTABLE.plist"
rm -f "$HOME/Library/Preferences/bugbear-crash-check.plist" "$HOME/Library/Preferences/bugbear-feedback-check.plist"
for leftover in "$HOME/Library/Preferences"/bugbear.selftest.*.plist; do
    if [ -e "$leftover" ]; then
        rm -f "$leftover"
    fi
done
done_step "Removed settings and caches"

# Temporary files: exports in progress and test leftovers.
temp_dir="${TMPDIR:-/tmp}"
rm -rf "${temp_dir%/}/${STORAGE_NAME:?}" "${temp_dir%/}/bugbear-feedback-check" "${temp_dir%/}/bugbear-crash-check"
done_step "Removed temporary files"

echo
echo "$APP_NAME is uninstalled. Your saved files stay in $exports_dir."
echo
echo "The bear will miss you. 🐻💧"
echo "If you have a minute, please tell us what you did not like:"
echo "the bear reads every answer and learns from it."
echo "  $FEEDBACK_URL"
# Asked only in the terminal that answered the first question; --yes runs never wait.
if [ "$ASK" = "1" ]; then
    printf "Open the feedback form? [Y/n] "
    read -r answer <&4 || answer="n"
    if [ "$answer" != "n" ] && [ "$answer" != "N" ] && [ "$answer" != "no" ]; then
        system open "$FEEDBACK_URL" || true
    fi
fi
echo "Thank you for giving $APP_NAME a try. Bye! 👋"
