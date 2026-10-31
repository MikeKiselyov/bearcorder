#!/bin/bash
# Builds the app ("<name>.app", the name from AppInfo.name) into ./build and signs it.
#
#   scripts/build-app.sh            release build
#   scripts/build-app.sh --run      build, then (re)launch the app
#   scripts/build-app.sh --install  build, then copy to /Applications (or ~/Applications) and launch
#   scripts/build-app.sh --install-only
#                                   the same install of the app already built in ./build: no swift build,
#                                   no signing (stops if there is no build). The test runs use it
#                                   after all.sh built the app once (APP_BUILT=1).
#
# Personal settings live in .env (git-ignored, see .env.example):
#   APP_BUNDLE_ID       bundle identifier (default io.github.<name>.app, scripts/lib/app-name.sh)
#   APP_SIGN_IDENTITY   codesign identity, e.g. "Apple Development: you@example.com (TEAMID)".
#                            Unset: the first "Apple Development" identity in the keychain, or without
#                            one a certificate made for this Mac (scripts/dev/local-signing.sh).
#                            "local": always that certificate. "-": ad-hoc signing (macOS asks for
#                            permissions again after each rebuild).
#
# --install replaces an installed copy with another bundle id together with its permissions, so System
# Settings lists the app once; macOS asks for the password for that (scripts/lib/permissions.sh).
# Only an earlier copy of this app (the same executable, a plain reverse-DNS id) is handled that way,
# and only a copy that is replaced: a copy in the other Applications folder stays and keeps its permissions.
# Another app where this one goes is never removed: the install stops.
# APP_KEEP_PERMISSIONS=1 skips the password and leaves the system's records alone.
#
# APP_AUTOMATION=1 builds the app the tests drive: with automation, the self-test and the media
# tools (Sources/App/DevTools). A release never has them. scripts/test/lib/test-app.sh sets it.
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

# What is left to undo when the script ends, however it ends: the local signing key is locked
# again, and copies of a replaced app kept aside for their permissions go.
uses_local_signing=0
kept_dir=""
on_exit() {
    if [ -n "$kept_dir" ]; then
        rm -rf "$kept_dir"
    fi
    if [ "$uses_local_signing" = 1 ]; then
        "$ROOT/scripts/dev/local-signing.sh" finish
    fi
}
trap on_exit EXIT

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/app-name.sh"
# shellcheck source=lib/permissions.sh
source "$ROOT/scripts/lib/permissions.sh"
# shellcheck source=lib/replace-app.sh
source "$ROOT/scripts/lib/replace-app.sh"
BUNDLE_ID="${APP_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
# APP_BUILD_DIR: a folder other than ./build (the script tests use one of their own).
BUILD_DIR="${APP_BUILD_DIR:-$ROOT/build}"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

# Where the app came from, so it can tell when the GitHub repository has newer changes
# and rebuild itself from this folder (see scripts/update.sh). Empty outside a git checkout.
COMMIT="$(git -C "$ROOT" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
BRANCH="$(git -C "$ROOT" symbolic-ref --short --quiet HEAD 2>/dev/null || true)"
REMOTE="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
REPOSITORY="$(echo "$REMOTE" | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed -E 's#\.git$##')"

# Builds, assembles and signs APP_DIR.
build_app() {
    # Marks a build with automation (what the tests drive); gone while a build runs or when it has none.
    rm -f "$BUILD_DIR/.automation-build"
    SWIFT_FLAGS=()
    if [ "${APP_AUTOMATION:-}" = "1" ]; then
        SWIFT_FLAGS=(-Xswiftc -DAUTOMATION)
        echo "==> swift build (release, with automation for the tests)"
    else
        echo "==> swift build (release)"
    fi
    swift build -c release --product App "${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}"
    BIN_DIR="$(swift build -c release --show-bin-path)"
    BINARY="$BIN_DIR/App"
    # The version is the newest release in WhatsNewCatalog.swift; the build number counts commits.
    VERSION="$("$BINARY" --version)"
    BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
    echo "==> version $VERSION ($BUILD_NUMBER)"

    echo "==> assembling $APP_DIR"
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
    # The App product is the executable; in the bundle it takes the app's name, so the process has it.
    cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"
    # The resources SwiftPM bundled (Sources/App/Resources): read through AppResources.
    cp -R "$BIN_DIR/App_App.bundle" "$APP_DIR/Contents/Resources/"
    # Debug symbols are not needed to run the app; without them it is a few MB lighter.
    strip -x "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true

    echo "==> rendering icon"
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"
    "$BINARY" --render-iconset "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"

    # Packaging/Info.plist holds the fixed keys; the values that depend on this build go in here.
    PLIST="$APP_DIR/Contents/Info.plist"
    cp "$ROOT/Packaging/Info.plist" "$PLIST"
    set_plist() {
        plutil -replace "$1" -string "$2" "$PLIST"
    }
    set_plist CFBundleIdentifier "$BUNDLE_ID"
    set_plist CFBundleExecutable "$APP_NAME"
    set_plist CFBundleName "$APP_NAME"
    set_plist CFBundleDisplayName "$APP_NAME"
    set_plist CFBundleShortVersionString "$VERSION"
    set_plist CFBundleVersion "$BUILD_NUMBER"
    set_plist NSCameraUsageDescription "$APP_NAME shows your webcam in a bubble on screen so it can be part of your recordings."
    set_plist NSMicrophoneUsageDescription "$APP_NAME records your voice with screen recordings when the microphone is turned on."
    set_plist NSAppleEventsUsageDescription "$APP_NAME reads the current browser tab URL to add it to the bug environment."
    set_plist SourceCommit "$COMMIT"
    set_plist SourceBranch "$BRANCH"
    set_plist SourceRepository "$REPOSITORY"
    set_plist SourcePath "$ROOT"
    plutil -lint "$PLIST" >/dev/null

    # Signing order: APP_SIGN_IDENTITY, then an Apple Development certificate, then a certificate
    # made for this Mac (scripts/dev/local-signing.sh). All three stay the same between builds, so macOS
    # keeps the permissions after an update. Ad-hoc ("-") is the last resort.
    IDENTITY="${APP_SIGN_IDENTITY:-}"
    if [ -z "$IDENTITY" ]; then
        IDENTITY="$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
    fi
    if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "local" ]; then
        IDENTITY="$("$ROOT/scripts/dev/local-signing.sh" identity || true)"
        # The key is usable only while this build signs (on_exit locks it).
        uses_local_signing=1
        if [ -n "$IDENTITY" ]; then
            echo "==> signing with the certificate made for this Mac (no Apple Development one)"
        fi
    fi
    if [ -z "$IDENTITY" ]; then
        IDENTITY="-"
        echo "!! No signing certificate; ad-hoc signing (macOS asks for permissions again after each update)"
    fi
    echo "==> signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
    codesign --verify --verbose=1 "$APP_DIR"

    # macOS caches app icons: re-register the bundle so the Dock, the screen recording indicator and
    # Finder show the current icon instead of an old one.
    touch "$APP_DIR" "$PLIST"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true

    if [ "${APP_AUTOMATION:-}" = "1" ]; then
        touch "$BUILD_DIR/.automation-build"
    fi
    echo "==> done: $APP_DIR"
}

INSTALL_ONLY=0
for argument in "$@"; do
    if [ "$argument" = "--install-only" ]; then
        INSTALL_ONLY=1
    fi
done
if [ "$INSTALL_ONLY" = 1 ]; then
    if [ ! -d "$APP_DIR" ]; then
        die "$APP_DIR is missing: run scripts/build-app.sh first"
    fi
    echo "==> installing the app built earlier: $APP_DIR"
    # Only a build sets the version; one from the environment or .env must not decide the check.
    VERSION=""
else
    build_app
fi

for argument in "$@"; do
    case "$argument" in
        --install|--install-only)
            # /Applications needs an admin account; everyone else gets ~/Applications.
            # APP_APPLICATIONS_DIR stands in for /Applications in the script tests.
            system_apps="${APP_APPLICATIONS_DIR:-/Applications}"
            TARGET_DIR="$system_apps"
            if [ ! -w "$TARGET_DIR" ]; then
                TARGET_DIR="$HOME/Applications"
                mkdir -p "$TARGET_DIR"
            fi
            installed_copies=("$system_apps/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app")
            # e2e tests install into a folder of their own.
            if [ -n "${APP_INSTALL_DIR:-}" ]; then
                TARGET_DIR="$APP_INSTALL_DIR"
                mkdir -p "$TARGET_DIR"
                installed_copies=("$TARGET_DIR/$APP_NAME.app")
            fi
            # A copy under another file name (renamed in Finder): the same bundle id and executable.
            # It counts as installed (an update keeps the settings) and is replaced, not left beside.
            renamed_copies=()
            for copy in "$TARGET_DIR"/*.app; do
                if [ "$copy" = "$TARGET_DIR/$APP_NAME.app" ] || [ ! -f "$copy/Contents/Info.plist" ]; then
                    continue
                fi
                copy_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$copy/Contents/Info.plist" 2>/dev/null || true)
                if [ "$copy_id" = "$BUNDLE_ID" ] && is_our_app "$copy" "$BUNDLE_ID"; then
                    renamed_copies+=("$copy")
                    installed_copies+=("$copy")
                fi
            done
            target_app="$TARGET_DIR/$APP_NAME.app"
            if { [ -e "$target_app" ] || [ -L "$target_app" ]; } && ! is_our_app "$target_app" "$BUNDLE_ID"; then
                die "$target_app is not a $APP_NAME build (its executable, bundle id or build keys differ), so it was not replaced. Move it away, then install again."
            fi
            already_installed=false
            for copy in "${installed_copies[@]}"; do
                if [ -d "$copy" ]; then
                    already_installed=true
                fi
            done
            # Replaced copies with another bundle id: kept aside until their permissions are gone.
            other_ids=()
            other_copies=()
            for copy in "$target_app" "${renamed_copies[@]+"${renamed_copies[@]}"}"; do
                if [ ! -d "$copy" ]; then
                    continue
                fi
                if copy_id=$(is_our_earlier_app "$copy" "$BUNDLE_ID"); then
                    # Without a copy the old id's permissions stay; the install goes on.
                    if [ -z "$kept_dir" ] && ! kept_dir="$(mktemp -d -t "$APP_SLUG-replaced")"; then
                        kept_dir=""
                        echo "==> could not keep a copy of $copy: the permissions of $copy_id stay"
                        continue
                    fi
                    kept="$kept_dir/${#other_ids[@]}/$(basename "$copy")"
                    if ! mkdir -p "$(dirname "$kept")" || ! cp -R "$copy" "$kept"; then
                        echo "==> could not keep a copy of $copy: the permissions of $copy_id stay"
                        continue
                    fi
                    other_ids+=("$copy_id")
                    other_copies+=("$kept")
                fi
            done
            pkill -x "$APP_NAME" 2>/dev/null || true
            wait_for_app_to_quit
            # No copy yet: a new person, or one who deleted the app. Settings outlive the app
            # in ~/Library/Preferences, so the welcome guide is shown again. An update keeps them.
            # After the quit, so a running copy cannot write them back.
            if [ "$already_installed" = false ]; then
                defaults delete "$BUNDLE_ID" onboardingCompleted 2>/dev/null || true
                defaults delete "$BUNDLE_ID" onboardingPage 2>/dev/null || true
                # Allow… asks macOS first again (SystemActions.askOnceThenOpenSettings).
                defaults delete "$BUNDLE_ID" askedPermission.Privacy_ScreenCapture 2>/dev/null || true
                defaults delete "$BUNDLE_ID" askedPermission.Privacy_Accessibility 2>/dev/null || true
                echo "==> new install: the welcome guide opens on launch"
            fi
            # The build goes in only when it is signed and reports its version; otherwise the
            # installed copy stays, and so do the renamed ones. VERSION is App --version of this
            # build; --install-only reads what the build wrote into its Info.plist.
            expected_version="${VERSION:-}"
            if [ -z "$expected_version" ]; then
                expected_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)
            fi
            had_copy=false
            if [ -e "$target_app" ]; then
                had_copy=true
            fi
            if ! replace_app "$APP_DIR" "$target_app" "$expected_version"; then
                # The old copy is back in place: it was quit for the install, so start it again.
                if [ "$had_copy" = true ] && [ -e "$target_app" ] && [ -z "${APP_NO_OPEN:-}" ]; then
                    open "$target_app" || true
                fi
                die "the app was not installed to $target_app"
            fi
            for copy in "${renamed_copies[@]+"${renamed_copies[@]}"}"; do
                echo "==> replacing $(basename "$copy"), the same app under another name"
                rm -rf "$copy"
            done
            echo "==> installed to $TARGET_DIR/$APP_NAME.app"
            for index in "${!other_ids[@]}"; do
                forget_permissions "${other_ids[$index]}" "${other_copies[$index]}"
            done
            if [ -n "$kept_dir" ]; then
                rm -rf "$kept_dir"
                kept_dir=""
            fi
            if [ -z "${APP_NO_OPEN:-}" ]; then
                open "$TARGET_DIR/$APP_NAME.app"
            fi
            ;;
        --run)
            pkill -x "$APP_NAME" 2>/dev/null || true
            wait_for_app_to_quit
            open "$APP_DIR"
            ;;
    esac
done
