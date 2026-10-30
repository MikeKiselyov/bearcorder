#!/bin/bash
# One-command uninstall: removes the app from this Mac - the app, captures, the screen buffer, logs,
# settings, permissions, the signing certificate and the source kept for updates (unless it has
# changes or commits of yours). Files you saved or exported stay where you put them.
#
#   curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bearcorder/main/scripts/uninstall.sh | bash
#   scripts/uninstall.sh --yes    # from a clone, without asking first
#
# Options (environment variables):
#   APP_SOURCE_DIR       where the installer kept the source (default: ~/.bearcorder)
#   APP_APPS_DIRS        folders to look for the app in, ":" between them
#                            (default: /Applications and ~/Applications)
#   APP_DRY_SYSTEM       1: print the steps that touch the running app, settings, permissions
#                            and keychains instead of doing them (for tests)
#   APP_LSREGISTER_DUMP  a file with the text of `lsregister -dump`, read instead of running it
#                            (the real dump takes 5-7 s; for tests)
#   APP_TTY              where the answers come from (default: /dev/tty; a file in tests)
#   APP_NO_DEVELOPER_TOOLS  1: act as if Command Line Tools and Xcode were missing (for tests)
#   NO_COLOR                 plain text
set -euo pipefail

# The name people see, also the executable and the folders' name. This file can run without the
# source, so it keeps its own copies; a unit test checks they match AppInfo.
APP_NAME="Bearcorder"
# The bundle id of copies built by the installer.
DEFAULT_BUNDLE_ID="io.github.bearcorder.app"
# Where people say why they left (.github/ISSUE_TEMPLATE/uninstall_feedback.yml).
FEEDBACK_URL="https://github.com/MikeKiselyov/bearcorder/issues/new?template=uninstall_feedback.yml"

SOURCE_DIR="${APP_SOURCE_DIR:-$HOME/.bearcorder}"
APPS_DIRS="${APP_APPS_DIRS:-/Applications:$HOME/Applications}"
DRY_SYSTEM="${APP_DRY_SYSTEM:-}"
TTY="${APP_TTY:-/dev/tty}"
LSREGISTER_DUMP="${APP_LSREGISTER_DUMP:-}"
SUPPORT_DIR="$HOME/Library/Application Support/$APP_NAME"
LOGS_DIR="$HOME/Library/Logs/$APP_NAME"
# Made by scripts/dev/local-signing.sh.
KEYCHAIN="$SUPPORT_DIR/Signing/local-signing.keychain-db"

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

# Bundle ids come from files (Info.plist, .env): only a plain reverse-DNS id is used in a path or a
# command, the same rule as scripts/lib/permissions.sh.
valid_id() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]
}

# A clone's own bundle id (.env).
clone_id=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$script_dir" ] && [ -f "$script_dir/../.env" ]; then
    clone_id=$(sed -n 's/^APP_BUNDLE_ID=//p' "$script_dir/../.env" | tr -d '"' | head -1)
fi

# A copy of the app, as build-app.sh tells: its executable is APP_NAME, and it has the keys every
# build writes or one of the app's bundle ids (the installer's, the clone's).
is_our_app() {
    local plist="$1/Contents/Info.plist"
    local app_id
    local executable
    app_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)
    executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null || true)
    if [ "$executable" != "$APP_NAME" ]; then
        return 1
    fi
    if [ -n "$app_id" ] && { [ "$app_id" = "$DEFAULT_BUNDLE_ID" ] || [ "$app_id" = "$clone_id" ]; }; then
        return 0
    fi
    if /usr/libexec/PlistBuddy -c "Print :SourcePath" "$plist" >/dev/null 2>&1; then
        return 0
    fi
    if /usr/libexec/PlistBuddy -c "Print :SourceCommit" "$plist" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Every installed copy, whatever it is called.
apps=()
IFS=':' read -r -a app_folders <<< "$APPS_DIRS"
for folder in "${app_folders[@]}"; do
    for app in "$folder"/*.app; do
        if [ ! -f "$app/Contents/Info.plist" ]; then
            continue
        fi
        if is_our_app "$app"; then
            apps+=("$app")
        fi
    done
done

# Settings are kept by bundle id: the installer's, every installed copy's, and a clone's own (.env).
bundle_ids=("$DEFAULT_BUNDLE_ID")
for app in "${apps[@]+"${apps[@]}"}"; do
    app_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null || true)
    if [ -n "$app_id" ] && ! valid_id "$app_id"; then
        echo "Skipped the settings of $app: its bundle id is not a plain reverse-DNS id."
        continue
    fi
    if [ -n "$app_id" ] && [[ " ${bundle_ids[*]} " != *" $app_id "* ]]; then
        bundle_ids+=("$app_id")
    fi
done
if [ -n "$clone_id" ] && valid_id "$clone_id" && [[ " ${bundle_ids[*]} " != *" $clone_id "* ]]; then
    bundle_ids+=("$clone_id")
fi

# The source kept for updates goes only when nothing in it would be lost: a git clone of its own with
# no changes and no commits that are not on its upstream. Otherwise it stays, and this says why.
# /usr/bin/git without Command Line Tools or Xcode shows macOS's dialog to install them, so git is
# run only when they are there. A file test and xcode-select, which never shows that dialog.
developer_tools_present() {
    if [ "${APP_NO_DEVELOPER_TOOLS:-}" = "1" ]; then
        return 1
    fi
    if [ -x /Library/Developer/CommandLineTools/usr/bin/git ]; then
        return 0
    fi
    local selected
    selected=$(xcode-select -p 2>/dev/null) || return 1
    [ -n "$selected" ] && [ -x "$selected/usr/bin/git" ]
}

source_kept_reason=""
if [ -e "$SOURCE_DIR" ] && ! developer_tools_present; then
    source_kept_reason="git is not installed (Command Line Tools or Xcode), so it could not be checked"
elif [ -e "$SOURCE_DIR" ]; then
    source_top=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
    if [ -z "$source_top" ] || ! [ "$source_top" -ef "$SOURCE_DIR" ]; then
        source_kept_reason="it is not a git clone"
    elif ! source_changes=$(git -C "$SOURCE_DIR" status --porcelain 2>/dev/null) || [ -n "$source_changes" ]; then
        source_kept_reason="it has changes that are not committed"
    elif ! source_commits=$(git -C "$SOURCE_DIR" rev-list HEAD --not '@{upstream}' 2>/dev/null); then
        source_kept_reason="its branch has no upstream to compare with"
    elif [ -n "$source_commits" ] || [ -n "$(git -C "$SOURCE_DIR" rev-list --branches --not --remotes 2>/dev/null)" ]; then
        source_kept_reason="it has commits that are not pushed"
    elif [ -n "$(git -C "$SOURCE_DIR" stash list 2>/dev/null)" ]; then
        source_kept_reason="it has stashed changes"
    fi
fi

# Where exports went, to say they stay.
exports_dir="$HOME/Desktop/$APP_NAME"
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
    if [ "$folder" = "$SOURCE_DIR" ] && [ -n "$source_kept_reason" ]; then
        continue
    fi
    if [ -e "$folder" ]; then
        size=$(du -sh "$folder" 2>/dev/null | cut -f1 | tr -d ' ')
        echo "  - $folder ${DIM}($size)${N}"
    fi
done
echo "  - permissions: Screen Recording, Accessibility, Microphone, Camera"
echo "  - settings, caches, the login item and temporary files"
echo
echo "Your saved files stay in $exports_dir."
if [ -n "$source_kept_reason" ]; then
    echo "$SOURCE_DIR stays: $source_kept_reason."
fi
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
if pgrep -x "$APP_NAME" >/dev/null 2>&1 || [ "$DRY_SYSTEM" = "1" ]; then
    system pkill -x "$APP_NAME" || true
    tries=0
    while [ "$DRY_SYSTEM" != "1" ] && pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$tries" -lt 50 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    if [ "$DRY_SYSTEM" != "1" ] && pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        pkill -9 -x "$APP_NAME" 2>/dev/null || true
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
    system "$app/Contents/MacOS/$APP_NAME" --forget-login-item >/dev/null 2>&1 || true
done
if [ ${#apps[@]} -gt 0 ]; then
    done_step "Removed the login item"
fi

# Permissions macOS gave the app; a new install asks again. Before the app goes: tccutil only
# resets a bundle id macOS still knows an app for, and refuses one whose app is gone. A record
# left like that ties the next install to the old id, and the app never shows up in the Screen
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
if [ -z "$source_kept_reason" ]; then
    forget_paths+=("$SOURCE_DIR/build/$APP_NAME.app")
fi
# The dump takes 5-7 s; tests give a small file instead.
remembered_dump() {
    if [ -n "$LSREGISTER_DUMP" ]; then
        cat "$LSREGISTER_DUMP"
    else
        "$LSREGISTER" -dump 2>/dev/null
    fi
}
if [ -x "$LSREGISTER" ] || [ -n "$LSREGISTER_DUMP" ]; then
    while IFS= read -r remembered; do
        if [ ! -e "$remembered" ] && [[ " ${forget_paths[*]} " != *" $remembered "* ]]; then
            forget_paths+=("$remembered")
        fi
    done < <(remembered_dump | sed -n "s|^path: *\(.*/$APP_NAME\.app\) (0x[0-9a-f]*)\$|\1|p" | sort -u)
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
if [ -n "$source_kept_reason" ]; then
    echo "   Kept $SOURCE_DIR: $source_kept_reason. Remove it yourself when you no longer need it."
elif [ -e "$SOURCE_DIR" ]; then
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
# Settings of debug runs from the source (.build/debug/App, Packaging/Debug-Info.plist), and scratch
# settings of the self-test and the automation checks (DevTools).
rm -f "$HOME/Library/Preferences/io.github.bearcorder.debug.plist"
rm -f "$HOME/Library/Preferences/$APP_NAME-crash-check.plist" "$HOME/Library/Preferences/$APP_NAME-feedback-check.plist"
for leftover in "$HOME/Library/Preferences/$APP_NAME".selftest.*.plist; do
    if [ -e "$leftover" ]; then
        rm -f "$leftover"
    fi
done
done_step "Removed settings and caches"

# Temporary files: exports in progress and test leftovers.
temp_dir="${TMPDIR:-/tmp}"
rm -rf "${temp_dir%/}/${APP_NAME:?}" "${temp_dir%/}/$APP_NAME-feedback-check" "${temp_dir%/}/$APP_NAME-crash-check"
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
