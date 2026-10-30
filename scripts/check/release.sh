#!/bin/bash
# Every change that reaches main is a new release: a pull request that touches the app
# must add a release on top of WhatsNewCatalog.swift with a higher version.
#
#   scripts/check/release.sh origin/main
#
# Changes only to docs (*.md, docs/) or CI (.github/) need no release.
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
BASE="${1:?usage: scripts/check/release.sh <base ref>}"
CATALOG="Sources/AppCore/Support/WhatsNewCatalog.swift"

# latest_version reads the top "version:" from catalog source on stdin; 0.0.0 when there is none.
latest_version() {
    local found
    found=$(grep -oE 'WhatsNewRelease\(id: *[0-9]+, *version: *"[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
    echo "${found:-0.0.0}"
}

merge_base=$(git merge-base "$BASE" HEAD)
app_changes=$(git diff --name-only "$merge_base" HEAD | grep -vE '(\.md$|^docs/|^\.github/)' || true)
if [ -z "$app_changes" ]; then
    echo "Only docs or CI changed, no release needed."
    exit 0
fi

new_source=$(cat "$CATALOG" 2>/dev/null || true)
# The catalog where it was at the base: a branch that moves it still compares with the old one.
old_catalog=$(git ls-tree -r --name-only "$merge_base" | grep '/WhatsNewCatalog\.swift$' | head -1 || true)
old_source=""
if [ -n "$old_catalog" ]; then
    old_source=$(git show "$merge_base:$old_catalog" 2>/dev/null || true)
fi
new_version=$(echo "$new_source" | latest_version)
old_version=$(echo "$old_source" | latest_version)
echo "Version on $BASE: $old_version, in this branch: $new_version"

highest=$(printf '%s\n%s\n' "$old_version" "$new_version" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
if [ "$new_version" = "$old_version" ] || [ "$highest" != "$new_version" ]; then
    echo
    echo "This branch changes the app but has no new release. Files:"
    while IFS= read -r changed_file; do
        echo "  $changed_file"
    done <<< "$app_changes"
    echo
    echo "Add a release on top of $CATALOG with the next id and a version above $old_version:"
    echo "a patch (x.y.Z) for fixes, a minor (x.Y.0) for new features. Write it for people, not as a commit list."
    exit 1
fi

if git rev-parse --verify --quiet "refs/tags/v$new_version" >/dev/null; then
    echo "Tag v$new_version already exists, pick a higher version."
    exit 1
fi
echo "Release $new_version is ready."
