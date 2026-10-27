#!/bin/bash
# Builds "Bugbear.app" into ./build and signs it.
#
#   scripts/build-app.sh            release build
#   scripts/build-app.sh --run      build, then (re)launch the app
#   scripts/build-app.sh --install  build, then copy to /Applications (or ~/Applications) and launch
#
# Personal settings live in .env (git-ignored, see .env.example):
#   BUGBEAR_BUNDLE_ID       bundle identifier (default io.github.bugbear.app)
#   BUGBEAR_SIGN_IDENTITY   codesign identity, e.g. "Apple Development: you@example.com (TEAMID)".
#                            Unset: the first "Apple Development" identity in the keychain, or without
#                            one a certificate made for this Mac (scripts/local-signing.sh).
#                            "local": always that certificate. "-": ad-hoc signing (macOS asks for
#                            permissions again after each rebuild).
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
ROOT="$(pwd)"
if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi
# shellcheck disable=SC1091
source "$ROOT/scripts/app-name.sh"
BUNDLE_ID="${BUGBEAR_BUNDLE_ID:-io.github.bugbear.app}"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

# Where the app came from, so it can tell when the GitHub repository has newer changes
# and rebuild itself from this folder (see scripts/update.sh). Empty outside a git checkout.
COMMIT="$(git -C "$ROOT" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
BRANCH="$(git -C "$ROOT" symbolic-ref --short --quiet HEAD 2>/dev/null || true)"
REMOTE="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
REPOSITORY="$(echo "$REMOTE" | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed -E 's#\.git$##')"

echo "==> swift build (release)"
swift build -c release --product Bugbear
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/Bugbear"
# The version is the newest release in WhatsNewCatalog.swift; the build number counts commits.
VERSION="$("$BINARY" --version)"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
echo "==> version $VERSION ($BUILD_NUMBER)"

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/Bugbear"
# Pictures for "What's new".
if [ -d "$ROOT/Resources/WhatsNew" ]; then
    cp -R "$ROOT/Resources/WhatsNew" "$APP_DIR/Contents/Resources/WhatsNew"
fi
# Debug symbols are not needed to run the app; without them it is a few MB lighter.
strip -x "$APP_DIR/Contents/MacOS/Bugbear" 2>/dev/null || true

echo "==> rendering icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
"$BINARY" --render-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Bugbear</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCameraUsageDescription</key><string>$APP_NAME shows your webcam in a bubble on screen so it can be part of your recordings.</string>
    <key>NSMicrophoneUsageDescription</key><string>$APP_NAME records your voice with screen recordings when the microphone is turned on.</string>
    <key>BugbearCommit</key><string>$COMMIT</string>
    <key>BugbearBranch</key><string>$BRANCH</string>
    <key>BugbearRepository</key><string>$REPOSITORY</string>
    <key>BugbearSourcePath</key><string>$ROOT</string>
    <key>NSAppleEventsUsageDescription</key><string>$APP_NAME reads the current browser tab URL to add it to the bug environment.</string>
</dict>
</plist>
PLIST

# Signing order: BUGBEAR_SIGN_IDENTITY, then an Apple Development certificate, then a certificate
# made for this Mac (scripts/local-signing.sh). All three stay the same between builds, so macOS
# keeps the permissions after an update. Ad-hoc ("-") is the last resort.
IDENTITY="${BUGBEAR_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "local" ]; then
    IDENTITY="$("$ROOT/scripts/local-signing.sh" identity || true)"
    # The key is usable only while this build signs.
    trap '"$ROOT/scripts/local-signing.sh" finish' EXIT
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
touch "$APP_DIR" "$APP_DIR/Contents/Info.plist"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true

echo "==> done: $APP_DIR"

for argument in "$@"; do
    case "$argument" in
        --install)
            # /Applications needs an admin account; everyone else gets ~/Applications.
            TARGET_DIR="/Applications"
            if [ ! -w "$TARGET_DIR" ]; then
                TARGET_DIR="$HOME/Applications"
                mkdir -p "$TARGET_DIR"
            fi
            installed_copies=("/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app")
            # e2e tests install into a folder of their own.
            if [ -n "${BUGBEAR_INSTALL_DIR:-}" ]; then
                TARGET_DIR="$BUGBEAR_INSTALL_DIR"
                mkdir -p "$TARGET_DIR"
                installed_copies=("$TARGET_DIR/$APP_NAME.app")
            fi
            # A copy under an earlier name (the app was renamed): same bundle id, other file name.
            # It counts as installed (an update keeps the settings) and is replaced, not left beside.
            renamed_copies=()
            for copy in "$TARGET_DIR"/*.app; do
                if [ "$copy" = "$TARGET_DIR/$APP_NAME.app" ] || [ ! -f "$copy/Contents/Info.plist" ]; then
                    continue
                fi
                copy_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$copy/Contents/Info.plist" 2>/dev/null || true)
                if [ "$copy_id" = "$BUNDLE_ID" ]; then
                    renamed_copies+=("$copy")
                    installed_copies+=("$copy")
                fi
            done
            already_installed=false
            for copy in "${installed_copies[@]}"; do
                if [ -d "$copy" ]; then
                    already_installed=true
                fi
            done
            pkill -x Bugbear 2>/dev/null || true
            wait_for_bugbear_to_quit
            # No Bugbear yet: a new person, or one who deleted the app. Settings outlive the app
            # in ~/Library/Preferences, so the welcome guide is shown again. An update keeps them.
            # After the quit, so a running copy cannot write them back.
            if [ "$already_installed" = false ]; then
                defaults delete "$BUNDLE_ID" onboardingCompleted 2>/dev/null || true
                defaults delete "$BUNDLE_ID" onboardingPage 2>/dev/null || true
                echo "==> new install: the welcome guide opens on launch"
            fi
            rm -rf "$TARGET_DIR/$APP_NAME.app"
            for copy in "${renamed_copies[@]+"${renamed_copies[@]}"}"; do
                echo "==> replacing $(basename "$copy"), the same app under its earlier name"
                rm -rf "$copy"
            done
            cp -R "$APP_DIR" "$TARGET_DIR/"
            echo "==> installed to $TARGET_DIR/$APP_NAME.app"
            if [ -z "${BUGBEAR_NO_OPEN:-}" ]; then
                open "$TARGET_DIR/$APP_NAME.app"
            fi
            ;;
        --run)
            pkill -x Bugbear 2>/dev/null || true
            wait_for_bugbear_to_quit
            open "$APP_DIR"
            ;;
    esac
done
