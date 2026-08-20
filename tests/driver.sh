#!/usr/bin/env bash
# Driver contract tests. These tests use temporary stage programs so they test
# the command-line driver without depending on a bootstrap build.
set -euo pipefail
cd "$(dirname "$0")/.."

DRIVER="${DRIVER:-bin/pascal1981}"
if [ ! -x "$DRIVER" ]; then
  echo "error: compiler driver '$DRIVER' not found. Run 'make driver' first." >&2
  exit 1
fi
DRIVER="$(realpath "$DRIVER")"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
stage_dir="$work_dir/stages"
mkdir -p "$stage_dir"

cat > "$stage_dir/cat-stage" <<'EOF'
#!/usr/bin/env bash
cat
EOF
chmod +x "$stage_dir/cat-stage"

cat > "$stage_dir/fail-stage" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
exit 23
EOF
chmod +x "$stage_dir/fail-stage"

pass=0
fail=0

expect_status() {
  local expected="$1"
  shift
  local actual=0
  "$@" > "$work_dir/stdout" 2> "$work_dir/stderr" || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL: expected status $expected, got $actual: $*" >&2
    cat "$work_dir/stderr" >&2
    fail=$((fail + 1))
    return
  fi
  pass=$((pass + 1))
}

expect_stderr() {
  local text="$1"
  if ! grep -qF -- "$text" "$work_dir/stderr"; then
    echo "FAIL: stderr did not contain: $text" >&2
    cat "$work_dir/stderr" >&2
    fail=$((fail + 1))
  fi
}

stage_env=(
  "PASCAL1981_LEXER=$stage_dir/cat-stage"
  "PASCAL1981_PARSER=$stage_dir/cat-stage"
  "PASCAL1981_TYPECHECKER=$stage_dir/cat-stage"
  "PASCAL1981_CODEGEN=$stage_dir/cat-stage"
)

expect_status 0 "$DRIVER" --version
if ! grep -qF 'pascal1981-native (Native Pascal Compiler Driver) 0.1.0' "$work_dir/stdout"; then
  echo 'FAIL: --version output changed' >&2
  fail=$((fail + 1))
fi

expect_status 1 "$DRIVER"
expect_stderr 'error: no input file specified'
expect_status 1 "$DRIVER" -o
expect_stderr 'error: -o requires an argument'
expect_status 1 "$DRIVER" --device-triple
expect_stderr 'error: --device-triple requires an argument'
expect_status 1 "$DRIVER" --unknown source.pas
expect_stderr 'error: unrecognized command line option: --unknown'

source_file="$work_dir/source with spaces; and dollars $.pas"
printf 'driver contract input\n' > "$source_file"
ir_file="$work_dir/output with spaces; and dollars $.ll"
expect_status 0 env "${stage_env[@]}" "$DRIVER" -S "$source_file" -o "$ir_file"
if ! cmp -s "$source_file" "$ir_file"; then
  echo 'FAIL: -S pipeline did not preserve the stage output' >&2
  fail=$((fail + 1))
fi

expect_status 1 env "${stage_env[@]}" "$DRIVER" -S "$source_file" "$source_file"
expect_stderr 'error: -c and -S require exactly one input file'

fail_env=("${stage_env[@]}")
fail_env[3]="PASCAL1981_CODEGEN=$stage_dir/fail-stage"
expect_status 23 env "${fail_env[@]}" "$DRIVER" -S "$source_file" -o "$work_dir/failed.ll"

if [ "$fail" -ne 0 ]; then
  echo "Driver contract results: $pass passed, $fail failed" >&2
  exit 1
fi

echo "Driver contract results: $pass passed"
