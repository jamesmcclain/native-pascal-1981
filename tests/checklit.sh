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
#   { CHECK-NOT: <substring that must not appear> }
#   { CHECK-ANY: <substring> || <alternative substring> }
#   { CHECK-COUNT: N <substring that must appear exactly N times> }
#   { CHECK-ENV: NAME=value }   (optional, sets an env var for this fixture's
#                                 codegen invocation, e.g. PASCAL_EMIT_PTX=1)
#   { CHECK-FLAGS: --opt val }  (optional, extra driver args for the compile,
#                                 e.g. --target-cpu x86-64-v3)
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
  done < <(grep -E '\{ *CHECK-ENV: *[A-Za-z_][A-Za-z0-9_]*=' "$fixture" \
              | sed -E 's/^.*\{ *CHECK-ENV: *//; s/ *\}[[:space:]]*$//')

  checks=()
  while IFS= read -r line; do
    checks+=("$line")
  done < <(grep -E '\{ *CHECK: *' "$fixture" \
              | sed -E 's/^.*\{ *CHECK: *//; s/ *\}[[:space:]]*$//')

  checks_not=()
  while IFS= read -r line; do
    checks_not+=("$line")
  done < <(grep -E '\{ *CHECK-NOT: *' "$fixture" \
              | sed -E 's/^.*\{ *CHECK-NOT: *//; s/ *\}[[:space:]]*$//')

  checks_any=()
  while IFS= read -r line; do
    checks_any+=("$line")
  done < <(grep -E '\{ *CHECK-ANY: *' "$fixture" \
              | sed -E 's/^.*\{ *CHECK-ANY: *//; s/ *\}[[:space:]]*$//')

  checks_count=()
  while IFS= read -r line; do
    checks_count+=("$line")
  done < <(grep -E '\{ *CHECK-COUNT: *[0-9]+ +' "$fixture" \
              | sed -E 's/^.*\{ *CHECK-COUNT: *//; s/ *\}[[:space:]]*$//')

  if [ ${#checks[@]} -eq 0 ] && [ ${#checks_not[@]} -eq 0 ] &&
     [ ${#checks_any[@]} -eq 0 ] && [ ${#checks_count[@]} -eq 0 ]; then
    echo "FAIL: $fixture (no CHECK directives found)" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' EXIT
  out_ll="$work_dir/out.ll"

  dialect="$(grep -E '^\{ *DIALECT: *(vintage|extended) *\}$' "$fixture" \
    | sed -E 's/^\{ *DIALECT: *//; s/ *\}$//' | head -n 1 || true)"
  dialect_args=()
  if [ -n "$dialect" ]; then
    dialect_args=(--dialect "$dialect")
  fi

  # CHECK-FLAGS: extra driver command-line arguments for this fixture's
  # compile (word-split on spaces). Used to exercise options like
  # --target-cpu / --target-features without environment variables.
  flag_args=()
  while IFS= read -r line; do
    # shellcheck disable=SC2206
    flag_args+=($line)
  done < <(grep -E '\{ *CHECK-FLAGS: *' "$fixture" \
              | sed -E 's/^.*\{ *CHECK-FLAGS: *//; s/ *\}[[:space:]]*$//')

  command=("$DRIVER" "${dialect_args[@]}" "${flag_args[@]}" -S "$fixture" -o "$out_ll")
  if [[ "$fixture" = *.check ]]; then
    input=$(grep -E '\{ *CHECK-INPUT: *' "$fixture" \
              | sed -E 's/^.*\{ *CHECK-INPUT: *//; s/ *\}[[:space:]]*$//' \
              | head -n 1)
    if [ -z "$input" ] || [ ! -f "$input" ]; then
      echo "FAIL: $fixture (missing or invalid CHECK-INPUT)" >&2
      FAILED=$((FAILED + 1))
      rm -rf "$work_dir"
      trap - EXIT
      continue
    fi
    command=(bin/codegen "${dialect_args[@]}")
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
    for pattern in "${checks_not[@]}"; do
      if grep -qF -- "$pattern" "$out_ll"; then
        echo "FAIL: $fixture (present CHECK-NOT: $pattern)" >&2
        ok=0
      fi
    done
    for alternatives in "${checks_any[@]}"; do
      found=0
      while IFS= read -r pattern; do
        if grep -qF -- "$pattern" "$out_ll"; then
          found=1
          break
        fi
      done < <(printf '%s\n' "$alternatives" | sed 's/ || /\n/g')
      if [ "$found" -eq 0 ]; then
        echo "FAIL: $fixture (missing CHECK-ANY: $alternatives)" >&2
        ok=0
      fi
    done
    for count_check in "${checks_count[@]}"; do
      expected=${count_check%% *}
      pattern=${count_check#* }
      actual=$(grep -oF -- "$pattern" "$out_ll" | wc -l || true)
      if [ "$actual" -ne "$expected" ]; then
        echo "FAIL: $fixture (CHECK-COUNT $pattern: expected $expected, got $actual)" >&2
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
