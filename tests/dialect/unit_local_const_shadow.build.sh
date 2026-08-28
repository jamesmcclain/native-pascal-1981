#!/usr/bin/env bash
# Run from this fixture's own directory so the sibling .inc resolves; the
# compile is expected to fail, and run.sh diffs the stderr against unit_local_const_shadow.err.
set -euo pipefail
"$1" unit_local_const_shadow.pas -o "$2"
