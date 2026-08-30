#!/usr/bin/env bash
# Replay the realistic completion corpus using the native Pascal client.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
compiler="$repo/bin/pascal1981"
proxy_bin="$repo/bin/pascal1981-proxy"
base_url=""
limit=0
verbose=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url) base_url="$2"; shift 2 ;;
        --proxy-bin) proxy_bin="$2"; shift 2 ;;
        --compiler) compiler="$2"; shift 2 ;;
        --limit) limit="$2"; shift 2 ;;
        -v|--verbose) verbose=1; shift ;;
        *) echo "usage: $0 [--base-url URL] [--proxy-bin PATH] [--compiler PATH] [--limit N]" >&2; exit 2 ;;
    esac
done

work="$(mktemp -d -t corpus-smoke-XXXXXX)"
stub_pid=""
proxy_pid=""
cleanup() {
    [[ -n "$proxy_pid" ]] && kill "$proxy_pid" 2>/dev/null || true
    [[ -n "$stub_pid" ]] && kill "$stub_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

cd "$here"
./corpus_smoke.build.sh "$compiler" "$work/corpus-smoke"
extended_compiler="$work/pascal1981-extended"
cat > "$extended_compiler" <<EOF
#!/usr/bin/env bash
exec "$compiler" --dialect extended "\$@"
EOF
chmod +x "$extended_compiler"
compiler="$extended_compiler"

if [[ -z "$base_url" ]]; then
    python3 "$here/stub_upstream.py" --port-file "$work/stub.port" >"$work/stub.log" 2>&1 &
    stub_pid=$!
    for _ in $(seq 50); do [[ -s "$work/stub.port" ]] && break; sleep 0.1; done
    [[ -s "$work/stub.port" ]] || { echo "stub upstream did not start" >&2; exit 1; }
    base_url="http://127.0.0.1:$(<"$work/stub.port")/v1"
fi

"$proxy_bin" --host 127.0.0.1 --port 0 --llm-base-url "$base_url" \
    --llm-model stub-model --max-tokens 512 --upstream-timeout 60 \
    --reasoning-effort none >"$work/proxy.log" 2>&1 &
proxy_pid=$!
for _ in $(seq 1200); do
    proxy_port="$(grep 'listening on http://' "$work/proxy.log" | tail -1 | grep -oE '127\.0\.0\.1:[0-9]+' | head -1 | cut -d: -f2 || true)"
    [[ -n "$proxy_port" ]] && break
    kill -0 "$proxy_pid" 2>/dev/null || { cat "$work/proxy.log" >&2; exit 1; }
    sleep 0.1
done
[[ -n "${proxy_port:-}" ]] || { echo "proxy did not start" >&2; cat "$work/proxy.log" >&2; exit 1; }

args=(--host 127.0.0.1 --port "$proxy_port" --corpus "$here/corpus" --limit "$limit" --timeout 60)
if [[ -n "${base_url:-}" && -z "${stub_pid:-}" ]]; then args+=(--compiler "$compiler"); fi
[[ "$verbose" = 1 ]] && cat "$work/proxy.log" >&2
"$work/corpus-smoke" "${args[@]}"
