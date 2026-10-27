#!/bin/bash
# Renames the app where people see the name: AppInfo.name, the installer's and uninstaller's copies, README.md
# and docs/*.md. Markdown cannot read a variable, so the text there is rewritten.
# What keeps the old name on purpose: folders with people's captures and logs
# (".../Application Support/Bugbear", ".../Logs/Bugbear", AppInfo.storageName), source paths
# (Sources/Bugbear, BugbearCore) and the executable.
#
#   scripts/rename-app.sh "New Name" [repository root]
set -euo pipefail

if [ $# -lt 1 ] || [ -z "$1" ]; then
    echo "usage: scripts/rename-app.sh \"New Name\" [repository root]" >&2
    exit 1
fi
NEW_NAME="$1"
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

python3 -I - "$ROOT" "$NEW_NAME" <<'PYTHON'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
new_name = sys.argv[2]

app_info = root / "Sources/BugbearCore/Support/AppInfo.swift"
app_info_text = app_info.read_text()
found = re.search(r'static let name = "(.*)"', app_info_text)
if found is None:
    sys.exit(f"no name in {app_info}")
old_name = found.group(1)
if old_name == new_name:
    print(f"the app is already called {new_name}")
    sys.exit(0)

app_info.write_text(app_info_text.replace(f'static let name = "{old_name}"', f'static let name = "{new_name}"'))

for script_name in ["install.sh", "uninstall.sh"]:
    script = root / "scripts" / script_name
    if not script.exists():
        continue
    script_text = script.read_text()
    script.write_text(script_text.replace(f'\nAPP_NAME="{old_name}"\n', f'\nAPP_NAME="{new_name}"\n'))

escaped = re.escape(old_name)
# One pass, so a new name that contains the old one ("Bugbear Pro") is not renamed twice:
# "Bugbear.app" anywhere, also inside a path like /Applications/Bugbear.app, or the name as a word
# in text, not inside a path (Support/Bugbear, Sources/Bugbear) or a longer word (BugbearCore).
name_pattern = re.compile(r"(?<!\w)" + escaped + r"(?=\.app\b)|(?<![/\w])" + escaped + r"(?![\w/])")


def slug(name):
    return name.lower().replace(" ", "-")


# Links to headings with the name in them: #where-bugbear-keeps-things.
anchor_pattern = re.compile(r"#[\w-]*\b" + re.escape(slug(old_name)) + r"\b[\w-]*")


def rename_anchor(found):
    return found.group(0).replace(slug(old_name), slug(new_name))


documents = [root / "README.md"]
documents.extend(sorted((root / "docs").glob("*.md")))
for document in documents:
    if not document.exists():
        continue
    text = document.read_text()
    text = name_pattern.sub(new_name, text)
    text = anchor_pattern.sub(rename_anchor, text)
    document.write_text(text)

print(f"renamed {old_name} to {new_name}: AppInfo.swift, scripts/install.sh, scripts/uninstall.sh, README.md, docs")
PYTHON
