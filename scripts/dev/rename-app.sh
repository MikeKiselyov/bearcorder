#!/bin/bash
# Renames the app. The code and the scripts take the name from AppInfo.name (scripts through
# scripts/lib/app-name.sh), so the executable, the folders on disk, the installer's bundle id and
# the GitHub repository follow it. This script writes the new name into AppInfo.swift and rewrites
# the places that cannot read it: the installer's and uninstaller's own copies, the bundle id of
# debug runs (Packaging/Debug-Info.plist) and the text for people (README.md, CONTRIBUTING.md, docs/*.md, the site files in docs/, the issue forms, .env.example).
# Pictures that show the name are made again with scripts/dev/readme-media.sh; the GitHub
# repository itself is renamed on GitHub.
#
#   scripts/dev/rename-app.sh "New Name" [repository root]
set -euo pipefail

if [ $# -lt 1 ] || [ -z "$1" ]; then
    echo "usage: scripts/dev/rename-app.sh \"New Name\" [repository root]" >&2
    exit 1
fi
NEW_NAME="$1"
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

python3 -I - "$ROOT" "$NEW_NAME" <<'PYTHON'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
new_name = sys.argv[2]

app_info = root / "Sources/AppCore/Support/AppInfo.swift"
app_info_text = app_info.read_text()
found = re.search(r'static let name = "(.*)"', app_info_text)
if found is None:
    sys.exit(f"no name in {app_info}")
old_name = found.group(1)
if old_name == new_name:
    print(f"the app is already called {new_name}")
    sys.exit(0)


# The same as AppInfo.slug: the repository, the bundle id and the source folder use it.
def slug(name):
    return name.lower().replace(" ", "-")


old_slug = slug(old_name)
new_slug = slug(new_name)

app_info.write_text(app_info_text.replace(f'static let name = "{old_name}"', f'static let name = "{new_name}"'))

# One pass, so a new name that contains the old one ("<old name> Pro") is not renamed twice.
# The name as a word, in text and in paths (/Applications/Name.app, Logs/Name/Name.log), and the
# slug outside a longer word (github.com/owner/slug, ~/.slug, io.github.slug.app, #where-slug-keeps-things).
name_pattern = re.compile(
    r"(?<![A-Za-z0-9])" + re.escape(old_name) + r"(?![A-Za-z0-9])"
    + r"|(?<![A-Za-z0-9])" + re.escape(old_slug) + r"(?![A-Za-z0-9])"
)


def rename(found):
    if found.group(0) == old_name:
        return new_name
    return new_slug


# The installer and uninstaller run without the source: their copies of the name, repository,
# bundle id and source folder.
for script_name in ["install.sh", "uninstall.sh"]:
    script = root / "scripts" / script_name
    if not script.exists():
        continue
    script_text = script.read_text()
    script_text = script_text.replace(f'\nAPP_NAME="{old_name}"\n', f'\nAPP_NAME="{new_name}"\n')
    script_text = re.sub(r"(?<=[/.])" + re.escape(old_slug) + r"(?![A-Za-z0-9])", new_slug, script_text)
    script.write_text(script_text)

# The bundle id of debug runs from the source.
debug_info = root / "Packaging/Debug-Info.plist"
if debug_info.exists():
    debug_text = debug_info.read_text()
    debug_info.write_text(debug_text.replace(f"io.github.{old_slug}.debug", f"io.github.{new_slug}.debug"))

documents = [root / "README.md", root / "CONTRIBUTING.md", root / ".env.example"]
documents.extend(sorted((root / "docs").glob("*.md")))
# The GitHub Pages site: the landing page, its config, robots.txt and the sitemap.
for site_pattern in ["*.html", "*.yml", "*.txt", "*.xml"]:
    documents.extend(sorted((root / "docs").glob(site_pattern)))
documents.extend(sorted((root / ".github/ISSUE_TEMPLATE").glob("*.yml")))
for document in documents:
    if not document.exists():
        continue
    text = document.read_text()
    document.write_text(name_pattern.sub(rename, text))

print(f"renamed {old_name} to {new_name}: AppInfo.swift, scripts/install.sh, scripts/uninstall.sh, Packaging/Debug-Info.plist, README.md, CONTRIBUTING.md, .env.example, docs, site, issue forms")
PYTHON
