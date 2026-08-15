#!/usr/bin/env bash
# Lightweight, zero-dependency POSIX Shell test runner for native-pascal-1981.
# Runs golden-file test fixtures, comparing exit code, stdout, and stderr.
#
# Usage:
#   ./tests/run.sh [options] [test_files...]
#
# Options:
#   -j, --jobs N      Run tests in parallel with N jobs (default: 1)
#   -v, --verbose     Show detailed output and diffs on failure
#   -h, --help        Show this help message
set -euo pipefail
cd "$(dirname "$0")/.."

DRIVER="bin/pascal1981-native"
if [ ! -x "$DRIVER" ]; then
  echo "error: compiler driver '$DRIVER' not found. Run 'make' and 'make bootstrap' first." >&2
  exit 1
fi

JOBS=1
VERBOSE=0
TEST_FILES=()

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
      echo "Usage: $0 [-j N] [-v] [test_files...]"
      exit 0
      ;;
    *)
      TEST_FILES+=("$1")
      shift
      ;;
  esac
done

if [ ${#TEST_FILES[@]} -eq 0 ]; then
  mapfile -t TEST_FILES < <(find tests/golden -name '*.pas' | sort)
fi

if [ ${#TEST_FILES[@]} -eq 0 ]; then
  echo "No tests found in tests/golden/."
  exit 0
fi

# Run single test
run_single_test() {
  local test_src="$1"
  local test_dir
  test_dir="$(dirname "$test_src")"
  local base_name
  base_name="$(basename "$test_src" .pas)"
  
  local expected_out="$test_dir/$base_name.out"
  if [ ! -f "$expected_out" ]; then
    expected_out="$test_dir/$base_name.expected"
  fi
  local expected_err="$test_dir/$base_name.err"
  local expected_code="$test_dir/$base_name.exitcode"
  
  local exp_code=0
  if [ -f "$expected_code" ]; then
    exp_code="$(cat "$expected_code" | tr -d ' \r\n')"
  fi

  local work_dir
  work_dir="$(mktemp -d)"

  local test_bin="$work_dir/$base_name"
  local actual_out="$work_dir/$base_name.actual.out"
  local actual_err="$work_dir/$base_name.actual.err"

  local compile_code=0
  "$DRIVER" "$test_src" -o "$test_bin" > "$work_dir/compile.out" 2> "$work_dir/compile.err" || compile_code=$?

  # Negative compilation test
  if [ "$exp_code" -ne 0 ] && [ ! -f "$expected_out" ]; then
    if [ "$compile_code" -ne 0 ]; then
      echo "PASS: $test_src (expected compilation failure)"
      rm -rf "$work_dir"
      return 0
    else
      echo "FAIL: $test_src (expected compile failure with code $exp_code, but compiled successfully)" >&2
      rm -rf "$work_dir"
      return 1
    fi
  fi

  if [ "$compile_code" -ne 0 ]; then
    echo "FAIL: $test_src (compilation failed with exit code $compile_code)" >&2
    if [ "$VERBOSE" -eq 1 ]; then
      cat "$work_dir/compile.err" >&2
    fi
    rm -rf "$work_dir"
    return 1
  fi

  local run_code=0
  "$test_bin" > "$actual_out" 2> "$actual_err" || run_code=$?

  if [ "$run_code" -ne "$exp_code" ]; then
    echo "FAIL: $test_src (expected exit code $exp_code, got $run_code)" >&2
    rm -rf "$work_dir"
    return 1
  fi

  if [ -f "$expected_out" ]; then
    if ! diff -u "$expected_out" "$actual_out" > "$work_dir/diff.out"; then
      echo "FAIL: $test_src (stdout mismatch)" >&2
      if [ "$VERBOSE" -eq 1 ]; then
        cat "$work_dir/diff.out" >&2
      fi
      rm -rf "$work_dir"
      return 1
    fi
  fi

  if [ -f "$expected_err" ]; then
    if ! diff -u "$expected_err" "$actual_err" > "$work_dir/diff_err.out"; then
      echo "FAIL: $test_src (stderr mismatch)" >&2
      if [ "$VERBOSE" -eq 1 ]; then
        cat "$work_dir/diff_err.out" >&2
      fi
      rm -rf "$work_dir"
      return 1
    fi
  fi

  rm -rf "$work_dir"
  echo "PASS: $test_src"
  return 0
}

export -f run_single_test
export DRIVER VERBOSE

TOTAL=${#TEST_FILES[@]}
echo "Running $TOTAL test(s) with concurrency $JOBS..."

TMP_RESULTS="$(mktemp -d)"
trap 'rm -rf "$TMP_RESULTS"' EXIT

if [ "$JOBS" -gt 1 ] && command -v xargs >/dev/null 2>&1; then
  printf '%s\n' "${TEST_FILES[@]}" | xargs -n 1 -P "$JOBS" bash -c '
    src="$1"
    res_file="'"$TMP_RESULTS"'/$(echo "$src" | tr "/" "_")"
    if run_single_test "$src"; then
      echo 0 > "$res_file"
    else
      echo 1 > "$res_file"
    fi
  ' _
else
  for src in "${TEST_FILES[@]}"; do
    res_file="$TMP_RESULTS/$(echo "$src" | tr "/" "_")"
    if run_single_test "$src"; then
      echo 0 > "$res_file"
    else
      echo 1 > "$res_file"
    fi
  done
fi

PASSED=0
FAILED=0

for res in "$TMP_RESULTS"/*; do
  if [ -f "$res" ]; then
    code="$(cat "$res")"
    if [ "$code" -eq 0 ]; then
      PASSED=$((PASSED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
  fi
done

echo "========================================"
echo "Test Results: $PASSED passed, $FAILED failed (total $TOTAL)"
echo "========================================"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
