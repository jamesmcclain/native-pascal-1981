#!/usr/bin/env bash
# Format C (GNU indent) and Python sources in place.
# find -exec is used instead of `$(find | grep ...)` so paths with
# whitespace can't word-split, and skips .git/venv/build byproducts.
set -euo pipefail
cd "$(dirname "$0")/.."

# Format C sources in runtime and driver
VERSION_CONTROL=none find runtime driver -name '*.c' -exec indent -kr -nut -l180 {} +

# Format Python test files if present
if find tests -name '*.py' 2>/dev/null | grep -q .; then
    if command -v isort >/dev/null 2>&1; then
        find tests -name '*.py' -not -path '*/__pycache__/*' -exec isort {} +
    fi
    if command -v yapf >/dev/null 2>&1; then
        find tests -name '*.py' -not -path '*/__pycache__/*' -exec yapf -i {} +
    fi
fi
