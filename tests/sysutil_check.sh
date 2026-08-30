#!/usr/bin/env bash
# Exercise the reusable filesystem and child-process substrate from Pascal.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
compiler="${1:-$repo/bin/pascal1981}"
if [[ "$compiler" != /* ]]; then
    compiler="$repo/$compiler"
fi
work="$(mktemp -d -t sysutil-check-XXXXXX)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

mkdir "$work/fixture" "$work/custom-tmp"
touch "$work/fixture/alpha" "$work/fixture/.hidden"
mkdir "$work/fixture/nested"
touch "$work/fixture/nested/child"
ln -s alpha "$work/fixture/alpha-link"

cd "$repo/src"
"$compiler" --dialect extended "$here/sysutil_check.pas" bytebuf.pas sysutil.pas -o "$work/sysutil_check"
# The grandchild-pipe timeout check hangs forever without the sysutil.c fix;
# bound the whole run so a regression fails instead of stalling the suite.
TMPDIR="$work/custom-tmp" timeout 15 "$work/sysutil_check" "$work/fixture" \
    "$work/custom-tmp" "$work/no-such-parent"
