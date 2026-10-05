#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# Every run and check fixture in the corpus, each against what it declares.
#
# The fixture corpus runner: every *.pas under tests/corpus/golden,
# integration, dialect and checklit, and every checklit/*.check, is compiled
# and checked against what the fixture itself declares.
#
# Usage:
#   ./tests/corpus/fixtures.sh [options] [fixture...]
#
# Options:
#   -j, --jobs N      Run N fixtures at once (default: $PASCAL_TEST_JOBS, else every CPU)
#   -v, --verbose     Show the diff or diagnostics of a failure
#   -h, --help        Show this help message
#
# A fixture is checked in one of two modes.
#
# Run mode (no CHECK directive): the fixture is compiled to an executable,
# run, and compared with its sidecar files, each optional:
#   <name>.out (or .expected)  exact stdout
#   <name>.err                 exact stderr (of the compile, when the
#                              fixture is expected not to compile)
#   <name>.exitcode            expected exit status (default 0); nonzero
#                              with no .out means the compile must fail
#   <name>.stdin               standard input
#   <name>.args                one argument per line (an argument naming an
#                              existing path is passed as its absolute path)
#   <name>.build.sh            replaces the plain driver invocation, for
#                              fixtures needing more than one compilation
#                              unit: run as `build.sh DRIVER OUTPUT` from
#                              the fixture's directory
# The program runs in an empty private directory.
#
# Check mode (any CHECK directive, or a .check file): the fixture is
# compiled to LLVM IR or PTX text (-S), or run through the stages that
# CHECK-STAGES names, and the text is checked:
#   { CHECK: text }            text appears in the output
#   { CHECK-NOT: text }        text does not appear
#   { CHECK-ANY: a || b }      one of the alternatives appears
#   { CHECK-COUNT: N text }    text appears exactly N times
#   { CHECK-FAIL: text }       the compile fails and text appears in its
#                              stderr; with a <name>.err sidecar, stderr
#                              must equal it exactly
#   { CHECK-FLAGS: args }      extra arguments for the driver, or for codegen
#                              alone in a CHECK-STAGES pipeline
#   { CHECK-ENV: NAME=value }  an environment variable for the compile
#   { CHECK-ASSEMBLE: ir }     the output is LLVM IR that the host C
#                              compiler must assemble
#   { CHECK-STAGES: s1 s2 ... } pipe the source through bin/<stage> for
#                              each named stage (lexer, parser, typechecker,
#                              codegen) instead of the driver; the last
#                              stage's stdout is the checked output
#   { CHECK-INPUT: path }      (.check files) what to compile, relative to
#                              the repository root: a typed AST (.json) fed
#                              to bin/codegen, or a Pascal source checked in
#                              place of the .check file itself
# Substrings are matched literally, in any order. A compile that succeeds
# must leave stderr empty.
#
# Both modes take a compile matrix: every cell is checked separately.
#   { DIALECT: vintage extended } each listed dialect (or a <name>.dialect
#                              sidecar); without one, the driver's default
#   { OPT: 0 1 2 3 }           each listed -O level; without one, the default
source tests/lib/fixture.sh

DRIVER="bin/pascal1981-native"
require "$DRIVER" bin/lexer bin/parser bin/typechecker bin/codegen

JOBS=$HARNESS_JOBS
VERBOSE=0
FIXTURES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -j|--jobs)
      JOBS="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [-j N] [-v] [fixture...]"
      exit 0
      ;;
    *)
      FIXTURES+=("$1")
      shift
      ;;
  esac
done

if [ ${#FIXTURES[@]} -eq 0 ]; then
  mapfile -t FIXTURES < <(find tests/corpus/golden tests/corpus/integration \
    tests/corpus/dialect tests/corpus/checklit \( -name '*.pas' -o -name '*.check' \) | sort)
fi

# Run mode, one cell: label src dialect opt.
run_cell() (
  local label=$1 test_src=$2 dialect=$3 opt=$4
  local test_dir base_name
  test_dir="$(dirname "$test_src")"
  base_name="$(basename "$test_src" .pas)"

  local expected_out="$test_dir/$base_name.out"
  if [ ! -f "$expected_out" ]; then
    expected_out="$test_dir/$base_name.expected"
  fi
  local expected_err="$test_dir/$base_name.err"
  local expected_code="$test_dir/$base_name.exitcode"

  local exp_code=0
  if [ -f "$expected_code" ]; then
    exp_code="$(tr -d ' \r\n' < "$expected_code")"
  fi

  local work_dir
  work_dir="$(mktemp -d)"
  trap 'rm -rf -- "$work_dir"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  local compile_args=()
  [ -z "$dialect" ] || compile_args+=(--dialect "$dialect")
  [ -z "$opt" ] || compile_args+=(-O"$opt")

  local test_bin="$work_dir/$base_name"
  local actual_out="$work_dir/$base_name.actual.out"
  local actual_err="$work_dir/$base_name.actual.err"

  local build_script="$test_dir/$base_name.build.sh"
  local compile_code=0
  if [ -f "$build_script" ]; then
    if [ -n "$opt" ]; then
      echo "FAIL: $label (an OPT matrix cannot apply to a .build.sh fixture)" >&2
      return 1
    fi
    local abs_driver driver_for_build
    abs_driver="$(realpath "$DRIVER")"
    driver_for_build="$abs_driver"
    if [ -n "$dialect" ]; then
      local shim_root="$work_dir/toolchain-shim"
      mkdir -p "$shim_root/bin" "$shim_root/runtime/build"
      ln -s "$(cd "$(dirname "$abs_driver")/../runtime/build" && pwd)/libpascalrt.a" \
        "$shim_root/runtime/build/libpascalrt.a"
      driver_for_build="$shim_root/bin/pascal1981-test-driver"
      cat > "$driver_for_build" <<EOF
#!/usr/bin/env bash
exec "$abs_driver" --dialect "$dialect" "\$@"
EOF
      cat > "$shim_root/bin/lexer" <<EOF
#!/usr/bin/env bash
exec "$(dirname "$abs_driver")/lexer" "\$@"
EOF
      for stage in parser typechecker codegen; do
        cat > "$shim_root/bin/$stage" <<EOF
#!/usr/bin/env bash
exec "$(dirname "$abs_driver")/$stage" --dialect "$dialect" "\$@"
EOF
      done
      chmod +x "$shim_root/bin/"*
    fi
    (cd "$test_dir" && bash "$(basename "$build_script")" "$driver_for_build" "$test_bin") \
      > "$work_dir/compile.out" 2> "$work_dir/compile.err" || compile_code=$?
  else
    "$DRIVER" "${compile_args[@]}" "$test_src" -o "$test_bin" > "$work_dir/compile.out" 2> "$work_dir/compile.err" || compile_code=$?
  fi

  # Negative compilation test. A sibling .err fixture, when present, also
  # verifies that diagnostics reach stderr rather than the pipeline's stdout.
  if [ "$exp_code" -ne 0 ] && [ ! -f "$expected_out" ]; then
    if [ "$compile_code" -eq 0 ]; then
      echo "FAIL: $label (expected compile failure with code $exp_code, but compiled successfully)" >&2
      return 1
    fi
    if [ -f "$expected_err" ] && ! diff -u "$expected_err" "$work_dir/compile.err" > "$work_dir/diff_err.out"; then
      echo "FAIL: $label (compile stderr mismatch)" >&2
      if [ "$VERBOSE" -eq 1 ]; then
        cat "$work_dir/diff_err.out" >&2
      fi
      return 1
    fi
    echo "PASS: $label (expected compilation failure)"
    return 0
  fi

  if [ "$compile_code" -ne 0 ]; then
    echo "FAIL: $label (compilation failed with exit code $compile_code)" >&2
    if [ "$VERBOSE" -eq 1 ]; then
      cat "$work_dir/compile.err" >&2
    fi
    return 1
  fi

  local stdin_file="$test_dir/$base_name.stdin"
  local args_file="$test_dir/$base_name.args"
  local run_args=()
  if [ -f "$args_file" ]; then
    mapfile -t run_args < "$args_file"
    # File-valued arguments were historically relative to the repository.
    # Preserve those read-only inputs while running in a private data directory.
    local arg_index
    for arg_index in "${!run_args[@]}"; do
      if [ -e "${run_args[$arg_index]}" ]; then
        run_args[$arg_index]="$(realpath "${run_args[$arg_index]}")"
      fi
    done
  fi
  local run_code=0
  if [ -f "$stdin_file" ]; then
    (cd "$work_dir" && exec "$test_bin" "${run_args[@]}") < "$stdin_file" > "$actual_out" 2> "$actual_err" || run_code=$?
  else
    (cd "$work_dir" && exec "$test_bin" "${run_args[@]}") > "$actual_out" 2> "$actual_err" || run_code=$?
  fi

  if [ "$run_code" -ne "$exp_code" ]; then
    echo "FAIL: $label (expected exit code $exp_code, got $run_code)" >&2
    return 1
  fi

  if [ -f "$expected_out" ]; then
    if ! diff -u "$expected_out" "$actual_out" > "$work_dir/diff.out"; then
      echo "FAIL: $label (stdout mismatch)" >&2
      if [ "$VERBOSE" -eq 1 ]; then
        cat "$work_dir/diff.out" >&2
      fi
      return 1
    fi
  fi

  if [ -f "$expected_err" ]; then
    if ! diff -u "$expected_err" "$actual_err" > "$work_dir/diff_err.out"; then
      echo "FAIL: $label (stderr mismatch)" >&2
      if [ "$VERBOSE" -eq 1 ]; then
        cat "$work_dir/diff_err.out" >&2
      fi
      return 1
    fi
  fi

  echo "PASS: $label"
  return 0
)

# Check mode, one cell: label fixture dialect opt.
check_cell() (
  local label=$1 fixture=$2 dialect=$3 opt=$4
  local work_dir line pattern ok status
  work_dir="$(mktemp -d)"
  trap 'rm -rf -- "$work_dir"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  local out_ll="$work_dir/out.ll" err="$work_dir/compile.err"

  local env_args=() flag_args=() stages=() checks=() checks_not=() checks_any=() checks_count=() checks_fail=()
  mapfile -t env_args < <(directive_values "$fixture" CHECK-ENV)
  mapfile -t checks < <(directive_values "$fixture" CHECK)
  mapfile -t checks_not < <(directive_values "$fixture" CHECK-NOT)
  mapfile -t checks_any < <(directive_values "$fixture" CHECK-ANY)
  mapfile -t checks_count < <(directive_values "$fixture" CHECK-COUNT)
  mapfile -t checks_fail < <(directive_values "$fixture" CHECK-FAIL)
  # shellcheck disable=SC2207
  flag_args=($(directive_values "$fixture" CHECK-FLAGS))
  # shellcheck disable=SC2207
  stages=($(directive_values "$fixture" CHECK-STAGES))
  local dialect_args=()
  [ -z "$dialect" ] || dialect_args=(--dialect "$dialect")

  local source=$fixture
  if [[ "$fixture" = *.check ]]; then
    source=$(directive_value "$fixture" CHECK-INPUT)
    if [ -z "$source" ] || [ ! -f "$source" ]; then
      echo "FAIL: $label (missing or invalid CHECK-INPUT)" >&2
      return 1
    fi
  fi
  status=0
  if [[ "$source" = *.json ]]; then
    env "${env_args[@]}" bin/codegen "${dialect_args[@]}" "${flag_args[@]}" < "$source" > "$out_ll" \
      2> "$err" || status=$?
  elif [ "${#stages[@]}" -gt 0 ]; then
    local stage input=$source next
    for stage in "${stages[@]}"; do
      case "$stage" in
        lexer | parser | typechecker | codegen) ;;
        *) echo "FAIL: $label (unknown CHECK-STAGES stage $stage)" >&2; return 1 ;;
      esac
      next=$work_dir/$stage.out
      # Like the driver, pass CHECK-FLAGS to codegen alone.
      local stage_flags=()
      [ "$stage" != codegen ] || stage_flags=("${flag_args[@]}")
      if ! env "${env_args[@]}" "bin/$stage" "${dialect_args[@]}" "${stage_flags[@]}" \
          < "$input" > "$next" 2>> "$err"; then
        status=1
        break
      fi
      input=$next
    done
    [ "$status" -ne 0 ] || cp "$input" "$out_ll"
  else
    local opt_args=()
    [ -z "$opt" ] || opt_args=(-O"$opt")
    env "${env_args[@]}" "$DRIVER" "${dialect_args[@]}" "${opt_args[@]}" "${flag_args[@]}" \
      -S "$source" -o "$out_ll" > "$work_dir/compile.out" 2> "$err" || status=$?
  fi

  if [ ${#checks_fail[@]} -gt 0 ]; then
    if [ "$status" -eq 0 ]; then
      echo "FAIL: $label (expected compilation failure, but succeeded)" >&2
      return 1
    fi
    ok=1
    for pattern in "${checks_fail[@]}"; do
      if ! grep -qF -- "$pattern" "$err"; then
        echo "FAIL: $label (missing CHECK-FAIL: $pattern)" >&2
        ok=0
      fi
    done
    local expected_err="${fixture%.*}.err"
    if [ -f "$expected_err" ] && ! diff -u "$expected_err" "$err" > "$work_dir/diff_err.out"; then
      echo "FAIL: $label (stderr differs from $expected_err)" >&2
      [ "$VERBOSE" -eq 0 ] || cat "$work_dir/diff_err.out" >&2
      ok=0
    fi
    if [ -s "$out_ll" ]; then
      echo "FAIL: $label (a failed compile left output)" >&2
      ok=0
    fi
    [ "$ok" -eq 1 ] || { cat "$err" >&2; return 1; }
    echo "PASS: $label"
    return 0
  fi

  if [ "$status" -ne 0 ]; then
    echo "FAIL: $label (compilation failed)" >&2
    cat "$err" >&2
    return 1
  fi
  ok=1
  if [ -s "$err" ]; then
    echo "FAIL: $label (the compile succeeded but wrote to stderr)" >&2
    cat "$err" >&2
    ok=0
  fi
  for pattern in "${checks[@]}"; do
    if ! grep -qF -- "$pattern" "$out_ll"; then
      echo "FAIL: $label (missing CHECK: $pattern)" >&2
      ok=0
    fi
  done
  for pattern in "${checks_not[@]}"; do
    if grep -qF -- "$pattern" "$out_ll"; then
      echo "FAIL: $label (present CHECK-NOT: $pattern)" >&2
      ok=0
    fi
  done
  local alternatives found
  for alternatives in "${checks_any[@]}"; do
    found=0
    while IFS= read -r pattern; do
      if grep -qF -- "$pattern" "$out_ll"; then
        found=1
        break
      fi
    done < <(printf '%s\n' "$alternatives" | sed 's/ || /\n/g')
    if [ "$found" -eq 0 ]; then
      echo "FAIL: $label (missing CHECK-ANY: $alternatives)" >&2
      ok=0
    fi
  done
  if [ "$(directive_value "$fixture" CHECK-ASSEMBLE)" = ir ] &&
      ! "${PASCAL1981_CC:-${CC:-clang}}" -x ir -c -o /dev/null "$out_ll" 2> "$work_dir/assemble.err"; then
    echo "FAIL: $label (the IR does not assemble)" >&2
    cat "$work_dir/assemble.err" >&2
    ok=0
  fi
  local count_check expected actual
  for count_check in "${checks_count[@]}"; do
    expected=${count_check%% *}
    pattern=${count_check#* }
    actual=$(grep -oF -- "$pattern" "$out_ll" | wc -l || true)
    if [ "$actual" -ne "$expected" ]; then
      echo "FAIL: $label (CHECK-COUNT $pattern: expected $expected, got $actual)" >&2
      ok=0
    fi
  done
  [ "$ok" -eq 1 ] || return 1
  echo "PASS: $label"
)

# One fixture: every cell of its matrix. Prints the cells' results; fails
# if any cell failed.
run_fixture() {
  local fixture=$1 mode=run dialect opt label failed=0 words
  local -a dialects opts
  if [[ "$fixture" = *.check ]] || grep -qE '\{ *CHECK(-[A-Z]+)?: ' "$fixture"; then
    mode=check
  elif [[ "$fixture" = tests/corpus/checklit/* ]]; then
    echo "FAIL: $fixture (no CHECK directives found)" >&2
    return 1
  fi
  words=$(fixture_dialects "$fixture") || {
    echo "FAIL: $fixture (invalid dialect)" >&2
    return 1
  }
  read -ra dialects <<< "$(echo $words)"
  read -ra opts <<< "$(directive_value "$fixture" OPT)"
  [ "${#dialects[@]}" -gt 0 ] || dialects=('')
  [ "${#opts[@]}" -gt 0 ] || opts=('')
  for dialect in "${dialects[@]}"; do
    for opt in "${opts[@]}"; do
      label=$fixture
      if [ "${#dialects[@]}" -gt 1 ] || [ "${#opts[@]}" -gt 1 ]; then
        label="$fixture [${dialect:-default}${opt:+ O$opt}]"
      fi
      if [ "$mode" = check ]; then
        check_cell "$label" "$fixture" "$dialect" "$opt" || failed=1
      else
        run_cell "$label" "$fixture" "$dialect" "$opt" || failed=1
      fi
    done
  done
  return "$failed"
}

export -f run_fixture run_cell check_cell directive_values directive_value fixture_dialects
export DRIVER VERBOSE

echo "Running ${#FIXTURES[@]} fixture(s) with concurrency $JOBS..."
results="$work/results"
mkdir "$results"
printf '%s\n' "${FIXTURES[@]}" | xargs -d '\n' -n 1 -P "$JOBS" bash -c '
  if run_fixture "$1"; then status=0; else status=1; fi
  echo "$status" > "$(mktemp "$0/result.XXXXXXXXXX")"
' "$results"

passed=$(cat "$results"/result.* 2> /dev/null | grep -cx 0 || true)
failed=$(cat "$results"/result.* 2> /dev/null | grep -cvx 0 || true)
echo "Fixture results: $passed passed, $failed failed (total ${#FIXTURES[@]})"
[ "$failed" -eq 0 ] && [ "$passed" -eq "${#FIXTURES[@]}" ]
