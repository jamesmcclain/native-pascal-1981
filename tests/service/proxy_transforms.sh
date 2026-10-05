#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Check proxycore's pure transforms against the frozen native golden corpus.
# Its data -- programs, corpus, goldens, stub backend -- is in tests/service/proxy/.
here=$ROOT/tests/service/proxy
compiler="${1:-$ROOT/bin/pascal1981}"
if [[ "$compiler" != /* ]]; then
    compiler="$ROOT/$compiler"
fi

cd "$here"
./transforms.build.sh "$compiler" "$work/transforms"
"$work/transforms" < transforms_golden.json
