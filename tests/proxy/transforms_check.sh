#!/usr/bin/env bash
# Check proxycore's pure transforms against the frozen native golden corpus.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
compiler="${1:-$repo/bin/pascal1981}"
if [[ "$compiler" != /* ]]; then
    compiler="$repo/$compiler"
fi
work="$(mktemp -d -t transforms-check-XXXXXX)"
trap 'rm -rf "$work"' EXIT

cd "$here"
./transforms.build.sh "$compiler" "$work/transforms"
"$work/transforms" < transforms_golden.json
