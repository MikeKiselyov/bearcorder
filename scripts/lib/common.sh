# shellcheck shell=bash
# Sourced by the scripts in scripts/, never run on its own. From a folder under scripts/:
#
#   # shellcheck source=../lib/common.sh
#   source "$(dirname "$0")/../lib/common.sh"
#
# ROOT is the repository, and the script continues from there. install.sh, update.sh and
# uninstall.sh do not use it: they run from a downloaded copy or an older checkout and have to
# work on their own.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

# die <message>: the script's name and the message on stderr, then exit 1.
die() {
    echo "$(basename "$0"): $*" >&2
    exit 1
}
