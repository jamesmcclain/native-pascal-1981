#!/usr/bin/env bash
# Remove build byproducts. Safe with spaces in paths and with zero matches.
set -euo pipefail
cd "$(dirname "$0")/.."

find . -type d -name '__pycache__' -prune -exec rm -rf {} +
make -C runtime clean 2>/dev/null || true
rm -rf build bin/pascal1981-native
