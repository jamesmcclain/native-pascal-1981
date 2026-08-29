#!/usr/bin/env bash
# Check a proxy implementation against the recorded conformance golden.
#
#   tests/proxy/run.sh                        # the Python reference
#   tests/proxy/run.sh bin/pascal1981-proxy   # the native port
#
# Both are driven through the same corpus against the same deterministic stub
# backend, so a difference in the report is a difference in the proxy. The
# golden was recorded from the Python reference and is the contract the port
# has to meet; regenerate it with --record only when the contract itself is
# meant to change.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
golden="$here/golden.json"

record=0
if [ "${1:-}" = "--record" ]; then
    record=1
    shift
fi

proxy="${1:-python3 $repo/tools/pascal1981_completion_proxy.py}"
out="$(mktemp -t proxy-conformance-XXXXXX.json)"
trap 'rm -f "$out"' EXIT

python3 "$here/run_conformance.py" --proxy-bin "$proxy" --out "$out" >/dev/null

if [ "$record" = 1 ]; then
    cp "$out" "$golden"
    echo "recorded $golden"
    exit 0
fi

if [ ! -f "$golden" ]; then
    echo "no golden at $golden; record one with: $0 --record" >&2
    exit 1
fi

echo "conformance: $proxy"
python3 "$here/run_conformance.py" --compare "$golden" "$out"
