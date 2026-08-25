#!/usr/bin/env bash
# Minimal, zero-Python, FileCheck-lite directive runner for asserting on
# emitted LLVM IR / PTX text -- the native-runner path for the class of
# test that (in tests/parity/) is done via Python string assertions on
# codegen output (kernel launch ABI, attribute placement, PTX directives).
# Those pytest-based assertions still exist and aren't being replaced;
# this gives new coverage of that shape a path that needs no Python.
#
# Fixture format: a .pas file under tests/checklit/ with one or more
# directive comments anywhere in the file. A .check file can instead feed a
# frozen typed AST directly to native codegen with CHECK-INPUT.
#
#   { CHECK: <substring that must appear in the emitted IR/PTX text> }
#   { CHECK-ENV: NAME=value }   (optional, sets an env var for this fixture's
#                                 codegen invocation, e.g. PASCAL_EMIT_PTX=1)
#   { CHECK-INPUT: path.json }  (required for .check files; path is relative
#                                 to the repository root)
#
# All CHECK substrings must be present somewhere in the output (order is
# not enforced -- this is deliberately simpler than real FileCheck; expand
# only if a real fixture needs ordering/DAG/COUNT semantics).
set -euo pipefail
cd "$(dirname "$0")/.."

DRIVER="bin/pascal1981-native"
if [ ! -x "$DRIVER" ]; then
  echo "error: compiler driver '$DRIVER' not found. Run 'make' and 'make bootstrap' first." >&2
  exit 1
fi

mapfile -t FIXTURES < <(find tests/checklit \( -name '*.pas' -o -name '*.check' \) 2>/dev/null | sort)

if [ ${#FIXTURES[@]} -eq 0 ]; then
  echo "No checklit fixtures found in tests/checklit/."
  exit 0
fi

PASSED=0
FAILED=0

for fixture in "${FIXTURES[@]}"; do
  env_args=()
  while IFS= read -r line; do
    env_args+=("$line")
  done < <(grep -oE '\{ *CHECK-ENV: *[A-Za-z_][A-Za-z0-9_]*=[^}]*\}' "$fixture" \
              | sed -E 's/\{ *CHECK-ENV: *//; s/ *\}//')

  checks=()
  while IFS= read -r line; do
    checks+=("$line")
  done < <(grep -oE '\{ *CHECK: *[^}]*\}' "$fixture" \
              | sed -E 's/\{ *CHECK: *//; s/ *\}$//')

  if [ ${#checks[@]} -eq 0 ]; then
    echo "FAIL: $fixture (no CHECK directives found)" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' EXIT
  out_ll="$work_dir/out.ll"

  command=("$DRIVER" -S "$fixture" -o "$out_ll")
  if [[ "$fixture" = *.check ]]; then
    input=$(grep -oE '\{ *CHECK-INPUT: *[^}]*\}' "$fixture" \
              | sed -E 's/\{ *CHECK-INPUT: *//; s/ *\}$//' | head -n 1)
    if [ -z "$input" ] || [ ! -f "$input" ]; then
      echo "FAIL: $fixture (missing or invalid CHECK-INPUT)" >&2
      FAILED=$((FAILED + 1))
      rm -rf "$work_dir"
      trap - EXIT
      continue
    fi
    command=(bin/codegen)
  fi

  status=0
  if [[ "$fixture" = *.check ]]; then
    env "${env_args[@]}" "${command[@]}" < "$input" > "$out_ll" \
      2> "$work_dir/compile.err" || status=$?
  else
    env "${env_args[@]}" "${command[@]}" > "$work_dir/compile.out" \
      2> "$work_dir/compile.err" || status=$?
  fi

  if [ "$status" -eq 0 ]; then
    ok=1
    for pattern in "${checks[@]}"; do
      if ! grep -qF -- "$pattern" "$out_ll"; then
        echo "FAIL: $fixture (missing CHECK: $pattern)" >&2
        ok=0
      fi
    done
    if [ "$ok" -eq 1 ]; then
      echo "PASS: $fixture"
      PASSED=$((PASSED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
  else
    echo "FAIL: $fixture (compilation failed)" >&2
    cat "$work_dir/compile.err" >&2
    FAILED=$((FAILED + 1))
  fi

  rm -rf "$work_dir"
  trap - EXIT
done

echo "========================================"
echo "Checklit Results: $PASSED passed, $FAILED failed (total ${#FIXTURES[@]})"
echo "========================================"

[ "$FAILED" -eq 0 ]
