#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# The driver: option parsing, stage dispatch, outputs and failure cleanup.
#
# These tests use temporary stage programs so they test the command-line
# driver without depending on a bootstrap build.

DRIVER="${DRIVER:-bin/pascal1981}"
if [ ! -x "$DRIVER" ]; then
  echo "error: compiler driver '$DRIVER' not found. Run 'make driver' first." >&2
  exit 1
fi
DRIVER="$(realpath "$DRIVER")"

stage_dir="$work/stages"
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

# LLVM's verifier aborts codegen with SIGABRT on a broken module, after the
# stage has written nothing.
cat > "$stage_dir/abort-stage" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
kill -ABRT $$
EOF
chmod +x "$stage_dir/abort-stage"

record_dir="$work/stage-args"
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

expect_status() {
  local expected="$1"
  shift
  local actual=0
  "$@" > "$work/stdout" 2> "$work/stderr" || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    fail "expected status $expected, got $actual: $*"
    cat "$work/stderr" >&2
    return
  fi
  pass
}

expect_stderr() {
  local text="$1"
  if ! grep -qF -- "$text" "$work/stderr"; then
    fail "stderr did not contain: $text"
    cat "$work/stderr" >&2
  fi
}

check_stage_args() {
  local dialect="$1"
  local label="$2"
  printf 'argc=0\n' > "$work/expected-lexer-args"
  printf 'argc=2\narg=--dialect\narg=%s\n' "$dialect" > "$work/expected-stage-args"
  for stage in lexer parser typechecker codegen; do
    local expected="$work/expected-stage-args"
    if [ "$stage" = lexer ]; then
      expected="$work/expected-lexer-args"
    fi
    if cmp -s "$expected" "$record_dir/$stage.args"; then
      pass
    else
      fail "$label: unexpected $stage argument array"
      diff -u "$expected" "$record_dir/$stage.args" >&2 || true
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
if ! grep -qF 'pascal1981-native (Native Pascal Compiler Driver) 0.1.0' "$work/stdout"; then
  fail '--version output changed'
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

source_file="$work/source with spaces; and dollars $.pas"
printf 'driver contract input\n' > "$source_file"
ir_file="$work/output with spaces; and dollars $.ll"
expect_status 0 env "${stage_env[@]}" "$DRIVER" -S "$source_file" -o "$ir_file"
if ! cmp -s "$source_file" "$ir_file"; then
  fail '-S pipeline did not preserve the stage output'
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
    -S "$source_file" -o "$work/$dialect_arg.ll"
  check_stage_args "$expected_dialect" "$dialect_arg dialect"
done

# The device / PTX and host target options are forwarded (as CLI args, never
# env) to the codegen stage only, appended after --dialect. --emit-ptx and
# --noalias-kernel-params forward as bare flags; the rest carry a value.
rm -f "$record_dir"/*.args
expect_status 0 env "${record_env[@]}" "$DRIVER" --dialect extended \
  --emit-ptx --device-triple nvptx64-nvidia-cuda --ptx-cpu sm_80 \
  --device-backend cuda --noalias-kernel-params \
  -S "$source_file" -o "$work/device-fwd.ll"
printf 'argc=10\narg=--dialect\narg=extended\narg=--emit-ptx\narg=--noalias-kernel-params\narg=--device-triple\narg=nvptx64-nvidia-cuda\narg=--ptx-cpu\narg=sm_80\narg=--device-backend\narg=cuda\n' \
  > "$work/expected-codegen-device-args"
if cmp -s "$work/expected-codegen-device-args" "$record_dir/codegen.args"; then
  pass
else
  fail "device options: unexpected codegen argument array"
  diff -u "$work/expected-codegen-device-args" "$record_dir/codegen.args" >&2 || true
fi
printf 'argc=2\narg=--dialect\narg=extended\n' > "$work/expected-device-plain-args"
for stage in parser typechecker; do
  if cmp -s "$work/expected-device-plain-args" "$record_dir/$stage.args"; then
    pass
  else
    fail "a device option leaked into the $stage stage"
    diff -u "$work/expected-device-plain-args" "$record_dir/$stage.args" >&2 || true
  fi
done

rm -f "$record_dir"/*.args
expect_status 0 env "${record_env[@]}" "$DRIVER" --dialect extended \
  --target-cpu skylake-avx512 --target-features +avx512f,+avx512vl \
  -S "$source_file" -o "$work/target-cpu.ll"
printf 'argc=6\narg=--dialect\narg=extended\narg=--target-cpu\narg=skylake-avx512\narg=--target-features\narg=+avx512f,+avx512vl\n' \
  > "$work/expected-codegen-target-args"
if cmp -s "$work/expected-codegen-target-args" "$record_dir/codegen.args"; then
  pass
else
  fail "--target-cpu/--target-features: unexpected codegen argument array"
  diff -u "$work/expected-codegen-target-args" "$record_dir/codegen.args" >&2 || true
fi
printf 'argc=2\narg=--dialect\narg=extended\n' > "$work/expected-plain-dialect-args"
for stage in parser typechecker; do
  if cmp -s "$work/expected-plain-dialect-args" "$record_dir/$stage.args"; then
    pass
  else
    fail "--target-cpu leaked into the $stage stage"
    diff -u "$work/expected-plain-dialect-args" "$record_dir/$stage.args" >&2 || true
  fi
done

expect_status 1 env "${stage_env[@]}" "$DRIVER" -S "$source_file" "$source_file"
expect_stderr 'error: -c, -S, --emit-ptx and --pretty-print require exactly one input file'

clang_log_ptx="$work/clang-ptx.log"
# --emit-ptx stops after codegen the way -S does: PTX is the codegen stage's
# final product, not something clang can be handed. Written any other way,
# the driver would pass PTX text to clang as if it were LLVM IR.
: > "$clang_log_ptx"
expect_status 0 env "${stage_env[@]}" "PASCAL1981_CC=$stage_dir/fake-clang" "PASCAL1981_FAKE_CLANG_LOG=$clang_log_ptx" \
  "$DRIVER" --emit-ptx "$source_file" -o "$work/device.ptx"
if ! cmp -s "$source_file" "$work/device.ptx"; then
  fail '--emit-ptx pipeline did not preserve the stage output'
fi
if [ -s "$clang_log_ptx" ]; then
  fail '--emit-ptx invoked clang'
  cat "$clang_log_ptx" >&2
fi

# ... and names its default output .ptx, not .ll.
(
  cd "$work"
  expect_status 0 env "${stage_env[@]}" "$DRIVER" --emit-ptx "$(basename "$source_file")"
)
if [ ! -f "${source_file%.pas}.ptx" ]; then
  fail 'default --emit-ptx output name was not created'
fi

expect_status 1 env "${stage_env[@]}" "$DRIVER" --emit-ptx -c "$source_file" -o "$work/device.o"
expect_stderr 'error: --emit-ptx and -c cannot be combined'

fail_env=("${stage_env[@]}")
fail_env[3]="PASCAL1981_CODEGEN=$stage_dir/fail-stage"
expect_status 23 env "${fail_env[@]}" "$DRIVER" -S "$source_file" -o "$work/failed.ll"
if [ -e "$work/failed.ll" ]; then
  fail 'a failed -S compile left its output file'
fi
abort_env=("${stage_env[@]}")
abort_env[3]="PASCAL1981_CODEGEN=$stage_dir/abort-stage"
expect_status 134 env "${abort_env[@]}" "$DRIVER" -S "$source_file" -o "$work/aborted.ll"
if [ -e "$work/aborted.ll" ]; then
  fail 'a -S compile whose stage aborted left its output file'
fi
# A failed stage removes only an output that this run created. A path that
# already existed (the user's file, a symlink, or a device such as
# /dev/null) stays.
printf 'old\n' > "$work/existing.ll"
expect_status 23 env "${fail_env[@]}" "$DRIVER" -S "$source_file" -o "$work/existing.ll"
if [ ! -e "$work/existing.ll" ]; then
  fail 'a failed -S compile removed an output file that already existed'
fi
: > "$work/link-target.ll"
ln -s "$work/link-target.ll" "$work/link.ll"
expect_status 23 env "${fail_env[@]}" "$DRIVER" -S "$source_file" -o "$work/link.ll"
if [ ! -L "$work/link.ll" ] || [ ! -e "$work/link-target.ll" ]; then
  fail 'a failed -S compile removed a symlink output or its target'
fi
expect_status 134 env "${abort_env[@]}" "PASCAL1981_CC=$stage_dir/fake-clang" "PASCAL1981_FAKE_CLANG_LOG=$work/abort-clang.log" "$DRIVER" -c "$source_file" -o "$work/aborted.o"
if [ -e "$work/abort-clang.log" ]; then
  fail 'the driver ran clang after a stage aborted'
fi

printf 'keep\n' > "$work/missing.ll"
expect_status 1 env "${stage_env[@]}" "$DRIVER" -S "$work/no-such-source.pas" -o "$work/missing.ll"
if [ ! -e "$work/missing.ll" ]; then
  fail 'an unreadable source removed an existing output file'
fi
mkdir "$work/not-a-source.pas"
expect_status 1 env "${stage_env[@]}" "$DRIVER" -S "$work/not-a-source.pas" -o "$work/directory.ll"
absent_env=("${stage_env[@]}")
absent_env[0]="PASCAL1981_LEXER=$stage_dir/no-such-stage"
expect_status 127 env "${absent_env[@]}" "$DRIVER" -S "$source_file" -o "$work/absent-stage.ll"

clang_log="$work/clang.log"
expect_status 37 env "${stage_env[@]}" "PASCAL1981_CC=$stage_dir/fake-clang" "PASCAL1981_FAKE_CLANG_LOG=$clang_log" "PASCAL1981_FAKE_CLANG_STATUS=37" "$DRIVER" -c "$source_file" -o "$work/source.o"

(
  cd "$work"
  expect_status 0 env "${stage_env[@]}" "$DRIVER" -S "$(basename "$source_file")"
)
if [ ! -f "${source_file%.pas}.ll" ]; then
  fail 'default -S output name was not created'
fi

: > "$clang_log"
second_source="$work/second source.pas"
printf 'second input\n' > "$second_source"
expect_status 0 env "${stage_env[@]}" "PASCAL1981_CC=$stage_dir/fake-clang" "PASCAL1981_FAKE_CLANG_LOG=$clang_log" "$DRIVER" "$source_file" "$second_source" -o "$work/multi"
if [ "$(grep -cF -- '--- clang invocation ---' "$clang_log")" -ne 2 ]; then
  fail 'multi-file link did not invoke clang once per extra object and once for the final link'
  cat "$clang_log" >&2
fi

# -O0..-O3 arrive as the glued short form of the -O integer option, and
# -I/-L/-l are pass-through prefixes forwarded to clang verbatim, in order,
# including repeated occurrences.
: > "$clang_log"
expect_status 0 env "${stage_env[@]}" "PASCAL1981_CC=$stage_dir/fake-clang" "PASCAL1981_FAKE_CLANG_LOG=$clang_log" \
  "$DRIVER" -c -O2 -I/inc -L/libdir -L/other -lm "$source_file" -o "$work/opt.o"
if ! grep -qxF -- '-O2' "$clang_log"; then
  fail '-O2 (glued short option) was not forwarded to clang'
fi
for tok in -I/inc -L/libdir -L/other -lm; do
  if ! grep -qxF -- "$tok" "$clang_log"; then
    fail "pass-through token $tok was not forwarded to clang"
  fi
done

expect_status 1 env "${stage_env[@]}" "$DRIVER" -O9 "$source_file"
expect_stderr 'error: optimization level must be 0, 1, 2, or 3'

# Opening the output truncates it before the lexer reads the input, so an
# output that names an input must be refused with the source left intact.
pretty_env=("${stage_env[@]}" "PASCAL1981_PRETTY81=$stage_dir/cat-stage")
guard_source="$work/guard.pas"
printf 'guard input\n' > "$guard_source"
cp "$guard_source" "$work/guard-original.pas"
# --pretty-print without -o writes to stdout; it used to default to the
# input's own name.
expect_status 0 env "${pretty_env[@]}" "$DRIVER" --pretty-print "$guard_source"
if ! cmp -s "$work/guard-original.pas" "$work/stdout"; then
  fail '--pretty-print without -o did not write the stage output to stdout'
fi
check_guard_source() {
  if ! cmp -s "$work/guard-original.pas" "$guard_source"; then
    fail "$1 changed the input file"
    cp "$work/guard-original.pas" "$guard_source"
  fi
}
check_guard_source '--pretty-print without -o'
expect_status 1 env "${pretty_env[@]}" "$DRIVER" --pretty-print "$guard_source" -o "$guard_source"
expect_stderr 'would overwrite an input file'
check_guard_source '--pretty-print -o <input>'
# A different spelling of the same path is the same file.
expect_status 1 env "${stage_env[@]}" "$DRIVER" -S "$guard_source" -o "$work/./guard.pas"
expect_stderr 'would overwrite an input file'
check_guard_source '-S -o <input>'
ln -s "$guard_source" "$work/guard-link.pas"
expect_status 1 env "${stage_env[@]}" "$DRIVER" -c "$guard_source" -o "$work/guard-link.pas"
expect_stderr 'would overwrite an input file'
check_guard_source '-c -o <symlink to input>'
# An input without the .pas suffix is its own default executable name.
bare_source="$work/bare"
cp "$guard_source" "$bare_source"
expect_status 1 env "${stage_env[@]}" "$DRIVER" "$bare_source"
expect_stderr 'would overwrite an input file'
if ! cmp -s "$work/guard-original.pas" "$bare_source"; then
  fail 'default output for a suffixless input changed the input file'
fi

finish "Driver contract"
