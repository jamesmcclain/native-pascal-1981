#!/usr/bin/env bash
# Run from this fixture's own directory so the sibling .inc files resolve.
set -euo pipefail
"$1" runtime_subrange.pas -o "$2"
