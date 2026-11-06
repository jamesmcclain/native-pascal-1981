#!/usr/bin/env bash
# Run from this fixture's own directory so the sibling .inc files resolve.
set -euo pipefail
"$1" parser_primary_after.pas -o "$2"
