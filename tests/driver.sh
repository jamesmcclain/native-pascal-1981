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

record_dir="$work_dir/stage-args"
mkdir -p "$record_dir"
for stage in lexer parser typechecker codegen; do
  cat > "$stage_dir/record-$stage" <<EOF
#!/usr/bin/env bash
{
  printf 'argc=%s\\n' "\$#"
  for arg in "\$@"; do
    printf 'arg=%s\\n' "\$arg"
  done
} > "\$PASCAL1981_STAGE_ARG_DIR/$stage.args"
cat
EOF
  chmod +x "$stage_dir/record-$stage"
done

cat > "$stage_dir/fake-clang" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '--- clang invocation ---' >> "$PASCAL1981_FAKE_CLANG_LOG"
printf '%s\n' "$@" >> "$PASCAL1981_FAKE_CLANG_LOG"
exit "${PASCAL1981_FAKE_CLANG_STATUS:-0}"
EOF
chmod +x "$stage_dir/fake-clang"

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

check_stage_args() {
  local dialect="$1"
  local label="$2"
  printf 'argc=0\n' > "$work_dir/expected-lexer-args"
  printf 'argc=2\narg=--dialect\narg=%s\n' "$dialect" > "$work_dir/expected-stage-args"
  for stage in lexer parser typechecker codegen; do
    local expected="$work_dir/expected-stage-args"
    if [ "$stage" = lexer ]; then
      expected="$work_dir/expected-lexer-args"
    fi
    if cmp -s "$expected" "$record_dir/$stage.args"; then
      pass=$((pass + 1))
    else
      echo "FAIL: $label: unexpected $stage argument array" >&2
      diff -u "$expected" "$record_dir/$stage.args" >&2 || true
      fail=$((fail + 1))
    fi
  done
}

stage_env=(
  "PASCAL1981_LEXER=$stage_dir/cat-stage"
  "PASCAL1981_PARSER=$stage_dir/cat-stage"
  "PASCAL1981_TYPECHECKER=$stage_dir/cat-stage"
  "PASCAL1981_CODEGEN=$stage_dir/cat-stage"
)
record_env=(
  "PASCAL1981_LEXER=$stage_dir/record-lexer"
  "PASCAL1981_PARSER=$stage_dir/record-parser"
  "PASCAL1981_TYPECHECKER=$stage_dir/record-typechecker"
  "PASCAL1981_CODEGEN=$stage_dir/record-codegen"
  "PASCAL1981_STAGE_ARG_DIR=$record_dir"
)

expect_status 0 "$DRIVER" --version
if ! grep -qF 'pascal1981-native (Native Pascal Compiler Driver) 0.1.0' "$work_dir/stdout"; then
  echo 'FAIL: --version output changed' >&2
  fail=$((fail + 1))
fi

expect_status 1 "$DRIVER"
expect_stderr 'error: no input file specified'
# Option-parsing diagnostics come from the shared argparse unit, so they read
# the same here as they do for the parser/typechecker/codegen stages.
expect_status 1 "$DRIVER" -o
expect_stderr 'option requires a value: -o'
expect_status 1 "$DRIVER" --device-triple
expect_stderr 'option requires a value: --device-triple'
expect_status 1 "$DRIVER" --dialect
expect_stderr 'option requires a value: --dialect'
expect_status 1 "$DRIVER" --dialect invalid
expect_stderr "error: invalid dialect 'invalid'; expected 'vintage' or 'extended'"
expect_status 1 "$DRIVER" --dialect device
expect_stderr "error: invalid dialect 'device'; expected 'vintage' or 'extended'"
expect_status 1 "$DRIVER" --unknown source.pas
expect_stderr 'unrecognized option: --unknown'

source_file="$work_dir/source with spaces; and dollars $.pas"
printf 'driver contract input\n' > "$source_file"
ir_file="$work_dir/output with spaces; and dollars $.ll"
expect_status 0 env "${stage_env[@]}" "$DRIVER" -S "$source_file" -o "$ir_file"
if ! cmp -s "$source_file" "$ir_file"; then
  echo 'FAIL: -S pipeline did not preserve the stage output' >&2
  fail=$((fail + 1))
fi

for dialect_arg in implicit vintage extended; do
  rm -f "$record_dir"/*.args
  driver_dialect_args=()
  expected_dialect="$dialect_arg"
  if [ "$dialect_arg" = implicit ]; then
    expected_dialect=vintage
  else
    driver_dialect_args=(--dialect "$dialect_arg")
  fi
  expect_status 0 env "${record_env[@]}" "$DRIVER" "${driver_dialect_args[@]}" \
    -S "$source_file" -o "$work_dir/$dialect_arg.ll"
  check_stage_args "$expected_dialect" "$dialect_arg dialect"
done

expect_status 1 env "${stage_env[@]}" "$DRIVER" -S "$source_file" "$source_file"
expect_stderr 'error: -c and -S require exactly one input file'

fail_env=("${stage_env[@]}")
fail_env[3]="PASCAL1981_CODEGEN=$stage_dir/fail-stage"
expect_status 23 env "${fail_env[@]}" "$DRIVER" -S "$source_file" -o "$work_dir/failed.ll"

expect_status 1 env "${stage_env[@]}" "$DRIVER" -S "$work_dir/no-such-source.pas" -o "$work_dir/missing.ll"
mkdir "$work_dir/not-a-source.pas"
expect_status 1 env "${stage_env[@]}" "$DRIVER" -S "$work_dir/not-a-source.pas" -o "$work_dir/directory.ll"
absent_env=("${stage_env[@]}")
absent_env[0]="PASCAL1981_LEXER=$stage_dir/no-such-stage"
expect_status 127 env "${absent_env[@]}" "$DRIVER" -S "$source_file" -o "$work_dir/absent-stage.ll"

clang_log="$work_dir/clang.log"
expect_status 37 env "${stage_env[@]}" "PASCAL1981_CC=$stage_dir/fake-clang" "PASCAL1981_FAKE_CLANG_LOG=$clang_log" "PASCAL1981_FAKE_CLANG_STATUS=37" "$DRIVER" -c "$source_file" -o "$work_dir/source.o"

(
  cd "$work_dir"
  expect_status 0 env "${stage_env[@]}" "$DRIVER" -S "$(basename "$source_file")"
)
if [ ! -f "${source_file%.pas}.ll" ]; then
  echo 'FAIL: default -S output name was not created' >&2
  fail=$((fail + 1))
fi

: > "$clang_log"
second_source="$work_dir/second source.pas"
printf 'second input\n' > "$second_source"
expect_status 0 env "${stage_env[@]}" "PASCAL1981_CC=$stage_dir/fake-clang" "PASCAL1981_FAKE_CLANG_LOG=$clang_log" "$DRIVER" "$source_file" "$second_source" -o "$work_dir/multi"
if [ "$(grep -cF -- '--- clang invocation ---' "$clang_log")" -ne 2 ]; then
  echo 'FAIL: multi-file link did not invoke clang once per extra object and once for the final link' >&2
  cat "$clang_log" >&2
  fail=$((fail + 1))
fi

# -O0..-O3 arrive as the glued short form of the -O integer option, and
# -I/-L/-l are pass-through prefixes forwarded to clang verbatim, in order,
# including repeated occurrences.
: > "$clang_log"
expect_status 0 env "${stage_env[@]}" "PASCAL1981_CC=$stage_dir/fake-clang" "PASCAL1981_FAKE_CLANG_LOG=$clang_log" \
  "$DRIVER" -c -O2 -I/inc -L/libdir -L/other -lm "$source_file" -o "$work_dir/opt.o"
if ! grep -qxF -- '-O2' "$clang_log"; then
  echo 'FAIL: -O2 (glued short option) was not forwarded to clang' >&2
  fail=$((fail + 1))
fi
for tok in -I/inc -L/libdir -L/other -lm; do
  if ! grep -qxF -- "$tok" "$clang_log"; then
    echo "FAIL: pass-through token $tok was not forwarded to clang" >&2
    fail=$((fail + 1))
  fi
done

expect_status 1 env "${stage_env[@]}" "$DRIVER" -O9 "$source_file"
expect_stderr 'error: optimization level must be 0, 1, 2, or 3'

if [ "$fail" -ne 0 ]; then
  echo "Driver contract results: $pass passed, $fail failed" >&2
  exit 1
fi

echo "Driver contract results: $pass passed"
