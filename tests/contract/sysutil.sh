#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Exercise the reusable filesystem and child-process substrate from Pascal.

compiler="${1:-$ROOT/bin/pascal1981}"
if [[ "$compiler" != /* ]]; then
    compiler="$ROOT/$compiler"
fi

mkdir "$work/fixture" "$work/custom-tmp"
touch "$work/fixture/alpha" "$work/fixture/.hidden"
mkdir "$work/fixture/nested"
touch "$work/fixture/nested/child"
ln -s alpha "$work/fixture/alpha-link"

cd src
"$compiler" --dialect extended "$ROOT/tests/contract/fixtures/sysutil_check.pas" bytebuf.pas sysutil.pas -o "$work/sysutil_check"
# The grandchild-pipe timeout check hangs forever without the sysutil.c fix;
# bound the whole run so a regression fails instead of stalling the suite.
TMPDIR="$work/custom-tmp" timeout 15 "$work/sysutil_check" "$work/fixture" \
    "$work/custom-tmp" "$work/no-such-parent"
