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

mkdir "$work/fixture"
touch "$work/fixture/alpha"
mkdir "$work/fixture/nested"

cd "$repo/src"
"$compiler" "$here/sysutil_check.pas" bytebuf.pas sysutil.pas -o "$work/sysutil_check"
"$work/sysutil_check" "$work/fixture"
