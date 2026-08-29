#!/usr/bin/env bash
# Check tests/proxy/oneshot.pas -- one upstream call, in Pascal -- against the
# deterministic stub backend.
#
#   tests/proxy/oneshot.sh                 # build with bin/pascal1981
#   tests/proxy/oneshot.sh path/to/compiler
#   tests/proxy/oneshot.sh --record        # re-record the expected output
#
# This is the step-5 milestone of the proxy port, kept as a check rather than
# a one-off because it is the only thing that exercises argparse, netsock,
# httpio's client side and jsonx together, end to end, over a real socket. It
# lives here and not in tests/integration/ because it needs a Python stub
# alongside it, which tests/run.sh has no way to start.
#
# For a live backend instead, run the binary by hand:
#   oneshot --base-url http://10.0.0.105:8080/v1 --prompt '...'
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
record=0
if [ "${1:-}" = "--record" ]; then
    record=1
    shift
fi
compiler="${1:-$repo/bin/pascal1981}"

work="$(mktemp -d -t oneshot-XXXXXX)"
stub_pid=""
cleanup() {
    [ -n "$stub_pid" ] && kill "$stub_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

cd "$here"
./oneshot.build.sh "$compiler" "$work/oneshot"

python3 "$here/stub_upstream.py" --port-file "$work/port" >"$work/stub.log" 2>&1 &
stub_pid=$!
for _ in $(seq 50); do
    [ -s "$work/port" ] && break
    sleep 0.1
done
[ -s "$work/port" ] || { echo "stub upstream did not start" >&2; exit 1; }
port="$(cat "$work/port")"
base="http://127.0.0.1:$port/v1"

# One case per reply shape the upstream can produce. The scenario is chosen by
# a marker in the prompt, which is how the stub stays header-free and
# deterministic; see stub_upstream.py.
{
    for scenario in ok fenced parts reasoning_exhausted no_choices \
                    null_content http_500 malformed; do
        echo "== $scenario"
        "$work/oneshot" --base-url "$base" \
                        --prompt "@@SCENARIO:$scenario@@ complete this" \
            && echo "exit=0" || echo "exit=$?"
    done
    echo "== payload"
    curl -s "http://127.0.0.1:$port/_last"
    echo
} >"$work/actual"

if [ "$record" = 1 ]; then
    cp "$work/actual" "$here/oneshot.expected"
    echo "recorded $here/oneshot.expected"
    exit 0
fi

if diff -u "$here/oneshot.expected" "$work/actual"; then
    echo "oneshot: all cases match"
else
    echo "oneshot: output differs from tests/proxy/oneshot.expected" >&2
    exit 1
fi
