#!/usr/bin/env bash
# Compile only: the disabled selector is deliberately out of bounds.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin/pascal1981 --dialect extended -S tests/fixtures/indexck_guard_ir.pas -o "$work/guard.ll"
# One checked selector, one unchecked: no branch or abort for a[3].
[ "$(grep -Ec '^index\.bad[0-9]*:' "$work/guard.ll")" -eq 1 ]
[ "$(grep -Ec '^index\.ok[0-9]*:' "$work/guard.ll")" -eq 1 ]
[ "$(grep -c 'call void @abort()' "$work/guard.ll")" -eq 1 ]
echo 'PASS: fixed-array INDEXCK guards only enabled selectors'
