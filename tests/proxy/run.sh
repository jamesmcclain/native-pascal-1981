#!/usr/bin/env bash
# Check a proxy implementation against the recorded conformance golden.
#
#   tests/proxy/run.sh                        # bin/pascal1981-proxy
#   tests/proxy/run.sh path/to/other-proxy    # any other implementation
#
# The implementation is driven through a fixed corpus against a deterministic
# stub backend, so a difference in the report is a difference in the proxy.
# The golden was recorded from the Python implementation this port replaced,
# and is the contract the port has to meet; regenerate it with --record only
# when the contract itself is meant to change.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
golden="$here/golden.json"

record=0
if [ "${1:-}" = "--record" ]; then
    record=1
    shift
fi

proxy="${1:-$repo/bin/pascal1981-proxy}"
out="$(mktemp -t proxy-conformance-XXXXXX.json)"
runner="$(mktemp -t proxy-conformance-runner-XXXXXX)"
trap 'rm -f "$out" "$runner"' EXIT

"$repo/tests/proxy/conformance_runner.build.sh" "$repo/bin/pascal1981" "$runner"
runner_args=(--proxy-bin "$proxy" --native-runner "$runner" --out "$out")
if [ "$record" = 0 ] && [ -f "$golden" ]; then runner_args+=(--golden "$golden"); fi
python3 "$here/run_conformance.py" "${runner_args[@]}" >/dev/null

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
