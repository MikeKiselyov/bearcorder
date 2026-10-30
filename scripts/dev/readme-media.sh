#!/bin/bash
# Regenerates the pictures and GIFs in docs/images that README.md shows.
#
#   scripts/dev/readme-media.sh
#
# Everything is rendered off screen from a made-up demo page (no screen access, no real captures).
# Needs ffmpeg for the GIFs: brew install ffmpeg
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
WORK="$ROOT/build/readme-media"
OUT="$ROOT/docs/images"

command -v ffmpeg >/dev/null || { echo "ffmpeg is needed: brew install ffmpeg"; exit 1; }

echo "==> rendering"
swift build >/dev/null
# English sizes and dates (1.5 GB, not 1,5 GB) whatever the Mac's region is.
"$(swift build --show-bin-path)/App" --readme-media "$WORK" -AppleLocale en_US -AppleLanguages "(en)" | tail -1
mkdir -p "$OUT"

# A GIF from numbered frames. Every frame shows for $3 seconds, the last one for $4.
make_gif() {
    local frames="$1" output="$2" step="$3" last="$4" width="$5"
    local list
    list="$WORK/$(basename "$output").txt"
    : > "$list"
    local previous=""
    {
        for frame in "$frames"/frame-*.png; do
            if [ -n "$previous" ]; then
                echo "file '$previous'"
                echo "duration $step"
            fi
            previous="$frame"
        done
        echo "file '$previous'"
        echo "duration $last"
        echo "file '$previous'"
    } >> "$list"
    ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" \
        -vf "scale=$width:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
        -loop 0 "$output"
}

echo "==> GIFs"
make_gif "$WORK/markup-frames" "$OUT/screenshot-editor.gif" 0.7 2.5 1000
make_gif "$WORK/install-frames" "$OUT/install.gif" 0.12 3 800
# For docs/features.md.
make_gif "$WORK/buffer-frames" "$OUT/buffer-save.gif" 1.6 2.5 900
make_gif "$WORK/report-frames" "$OUT/bug-report.gif" 2 3.5 1000

# The menu tabs one after another.
mkdir -p "$WORK/menu-frames"
rm -f "$WORK/menu-frames"/*.png
number=0
for tab in record capture tools recent; do
    cp "$WORK/screens/menu-$tab.png" "$(printf "$WORK/menu-frames/frame-%03d.png" $number)"
    number=$((number + 1))
done
make_gif "$WORK/menu-frames" "$OUT/menu.gif" 1.8 1.8 720

echo "==> pictures"
picture() {
    ffmpeg -loglevel error -y -i "$WORK/screens/$1.png" -vf "scale=$2:-1:flags=lanczos" "$OUT/$1.png"
}
# Saved under the names features.md links. The Space pictures have smooth gradients and get a 256 color palette.
palette_picture() {
    ffmpeg -loglevel error -y -i "$WORK/screens/$1.png" \
        -vf "scale=$3:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse=dither=bayer:bayer_scale=5" "$OUT/$2.png"
}
picture video-editor 1220
picture history 980
picture record-area-picker 1200
picture record-outline-area 1200
picture video-crop 960
picture toolbox-json 1220
picture toolbox-timezones 1220
picture toolbox-testdata 1220
picture onboarding-2 680
picture settings 560
# For docs/features.md.
picture settings-permissions 560
picture settings-bug-reports 560
picture hud-drawing 720
picture menu-space 360
picture toolbox-jsondiff 1220
picture feedback-problem 560
picture compare 1000
picture step-guide 700
picture layout-measure 960
picture layout-design 960
palette_picture space-review-category space-review 900
palette_picture space-window-find space-window 1000
ffmpeg -loglevel error -y -i "$WORK/screens/toolbox-colorcontrast.png" -vf "scale=1000:-1:flags=lanczos" "$OUT/layout-contrast.png"
cp "$WORK/screens/logo.png" "$OUT/logo.png"

du -sh "$OUT"
ls -1 "$OUT"
