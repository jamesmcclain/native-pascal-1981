#!/usr/bin/env bash
# Run from this fixture's own directory so the sibling .inc resolves. The
# host PROGRAM is a .host file because every .pas here is a test of its own.
set -euo pipefail
"$1" unit_forward_pointer.host unit_forward_pointer.pas -o "$2"
