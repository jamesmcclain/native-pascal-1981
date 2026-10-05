#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Compile recorded reference continuations with the native compiler.
# Its data -- programs, corpus, goldens, stub backend -- is in tests/service/proxy/.
here=$ROOT/tests/service/proxy
compiler="${1:-$ROOT/bin/pascal1981}"
if [[ "$compiler" != /* ]]; then
    compiler="$ROOT/$compiler"
fi
tmp_root="$work/tmp"
mkdir "$tmp_root"

check_empty_tmp() {
    if [[ -n "$(find "$tmp_root" -mindepth 1 -print -quit)" ]]; then
        echo "corpus reference leaked a temporary directory" >&2
        return 1
    fi
}

cd "$here"
./corpus_reference.build.sh "$compiler" "$work/corpus-reference"
extended_compiler="$work/pascal1981-extended"
cat > "$extended_compiler" <<EOF
#!/usr/bin/env bash
exec "$compiler" --dialect extended "\$@"
EOF
chmod +x "$extended_compiler"
TMPDIR="$tmp_root" "$work/corpus-reference" "$here/corpus" "$extended_compiler" "$(dirname "$ROOT")"
check_empty_tmp
if TMPDIR="$tmp_root" "$work/corpus-reference" "$work/no-such-corpus" "$extended_compiler" "$(dirname "$ROOT")" \
    >/dev/null 2>&1; then
    echo "corpus reference accepted a nonexistent corpus directory" >&2
    exit 1
fi
check_empty_tmp
