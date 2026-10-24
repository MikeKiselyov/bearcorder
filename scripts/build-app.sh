#!/bin/bash
# Builds "QA Helper.app" into ./build and signs it.
#
#   scripts/build-app.sh            release build
#   scripts/build-app.sh --run      build, then (re)launch the app
#   scripts/build-app.sh --install  build, then copy to /Applications (or ~/Applications) and launch
#
# Personal settings live in .env (git-ignored, see .env.example):
#   QAHELPER_BUNDLE_ID       bundle identifier (default io.github.qahelper.app)
#   QAHELPER_SIGN_IDENTITY   codesign identity, e.g. "Apple Development: you@example.com (TEAMID)".
#                            Unset: the first "Apple Development" identity in the keychain is used.
#                            "-": ad-hoc signing (macOS asks for permissions again after each rebuild).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi
APP_NAME="QA Helper"
BUNDLE_ID="${QAHELPER_BUNDLE_ID:-io.github.qahelper.app}"
VERSION="${QAHELPER_VERSION:-0.1.0}"
BUILD_NUMBER="${QAHELPER_BUILD:-1}"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

# Where the app came from, so it can tell when the GitHub repository has newer changes
# and rebuild itself from this folder (see scripts/update.sh). Empty outside a git checkout.
COMMIT="$(git -C "$ROOT" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
BRANCH="$(git -C "$ROOT" symbolic-ref --short --quiet HEAD 2>/dev/null || true)"
REMOTE="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
REPOSITORY="$(echo "$REMOTE" | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed -E 's#\.git$##')"

echo "==> swift build (release)"
swift build -c release --product QAHelper
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/QAHelper"

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/QAHelper"

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
    <key>CFBundleExecutable</key><string>QAHelper</string>
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
    <key>NSCameraUsageDescription</key><string>QA Helper shows your webcam in a bubble on screen so it can be part of your recordings.</string>
    <key>NSMicrophoneUsageDescription</key><string>QA Helper records your voice with screen recordings when the microphone is turned on.</string>
    <key>QAHelperCommit</key><string>$COMMIT</string>
    <key>QAHelperBranch</key><string>$BRANCH</string>
    <key>QAHelperRepository</key><string>$REPOSITORY</string>
    <key>QAHelperSourcePath</key><string>$ROOT</string>
    <key>NSAppleEventsUsageDescription</key><string>QA Helper reads the current browser tab URL to add it to the bug environment.</string>
</dict>
</plist>
PLIST

IDENTITY="${QAHELPER_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY="-"
    echo "!! No Apple Development identity found; ad-hoc signing (permissions reset on every rebuild)"
fi
echo "==> signing with: $IDENTITY"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
codesign --verify --verbose=1 "$APP_DIR"

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
            pkill -x QAHelper 2>/dev/null || true
            sleep 0.5
            rm -rf "$TARGET_DIR/$APP_NAME.app"
            cp -R "$APP_DIR" "$TARGET_DIR/"
            echo "==> installed to $TARGET_DIR/$APP_NAME.app"
            open "$TARGET_DIR/$APP_NAME.app"
            ;;
        --run)
            pkill -x QAHelper 2>/dev/null || true
            sleep 0.5
            open "$APP_DIR"
            ;;
    esac
done
