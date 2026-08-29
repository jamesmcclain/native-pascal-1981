#!/usr/bin/env bash
# Compile recorded reference continuations with the native compiler.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
compiler="${1:-$repo/bin/pascal1981}"
if [[ "$compiler" != /* ]]; then
    compiler="$repo/$compiler"
fi
work="$(mktemp -d -t corpus-reference-XXXXXX)"
trap 'rm -rf "$work"' EXIT

cd "$here"
./corpus_reference.build.sh "$compiler" "$work/corpus-reference"
"$work/corpus-reference" "$here/corpus" "$compiler"
