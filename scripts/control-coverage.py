#!/usr/bin/env python3
"""Every control has a check that presses it (scripts/controls.txt).

  scripts/control-coverage.py              each row's check exists in the tests
  scripts/control-coverage.py <listing>    each control in a live listing has a row; a listing
                                           line is "area|role|label", from the e2e tests
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST_FILES = [
    ROOT / "scripts" / "e2e.sh",
    ROOT / "scripts" / "e2e-features.sh",
    ROOT / "Sources" / "Bugbear" / "DevTools" / "DevChecks.swift",
]


def app_name():
    source = (ROOT / "Sources" / "BugbearCore" / "Support" / "AppInfo.swift").read_text()
    match = re.search(r'static let name = "(.*)"', source)
    if match is None:
        print("no app name in AppInfo.swift")
        sys.exit(2)
    return match.group(1)


def read_rows():
    name = re.escape(app_name())
    rows = []
    for number, line in enumerate((ROOT / "scripts" / "controls.txt").read_text().splitlines(), start=1):
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            print(f"controls.txt:{number}: needs area, pattern and check separated by tabs")
            sys.exit(2)
        pattern = parts[1].replace("{app}", name)
        rows.append({"line": number, "area": parts[0], "pattern": pattern, "check": parts[2]})
    return rows


def check_rows_have_tests(rows):
    # Quotes inside the scripts' strings are escaped; compare without the backslashes.
    tests = ""
    for path in TEST_FILES:
        tests += path.read_text().replace("\\", "")
    missing = 0
    for row in rows:
        if row["check"].replace("\\", "") not in tests:
            print(f"controls.txt:{row['line']}: no test has \"{row['check']}\"")
            missing += 1
    return missing


def row_covers(row, area, label):
    area_matches = row["area"] == area
    if row["area"].endswith("/*") and area.startswith(row["area"][:-1]):
        area_matches = True
    if not area_matches:
        return False
    return re.fullmatch(row["pattern"], label) is not None


def check_live_controls(rows, listing):
    uncovered = 0
    for line in Path(listing).read_text().splitlines():
        if not line.strip():
            continue
        parts = line.split("|", 2)
        if len(parts) != 3:
            continue
        area = parts[0]
        label = parts[2]
        covered = False
        for row in rows:
            if row_covers(row, area, label):
                covered = True
                break
        if not covered:
            print(f"no check for {area}: \"{label}\" ({parts[1]}); add a row to scripts/controls.txt and a test")
            uncovered += 1
    return uncovered


def main():
    rows = read_rows()
    problems = check_rows_have_tests(rows)
    if len(sys.argv) > 1:
        problems += check_live_controls(rows, sys.argv[1])
    if problems:
        print(f"{problems} control coverage problem(s)")
        sys.exit(1)
    print(f"control coverage ok: {len(rows)} rows")


main()
