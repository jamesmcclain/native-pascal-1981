#!/usr/bin/env bash
# Run from this fixture's own directory so the sibling .inc resolves. The
# host PROGRAM is a .host file because every .pas here is a test of its own.
set -euo pipefail
"$1" unit_local_type_shadow.host unit_local_type_shadow.pas -o "$2"
