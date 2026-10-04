#!/usr/bin/env bash
# Run from this fixture's own directory so the sibling .inc resolves; the
# compile is expected to fail, and run.sh diffs the stderr against unit_const_iface_mismatch.err.
set -euo pipefail
"$1" unit_const_iface_mismatch.pas -o "$2"
