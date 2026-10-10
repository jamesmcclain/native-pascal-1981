#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# The driver links REAL math builtins at every optimization level without user -lm.
require bin/pascal1981
# READ prevents optimization from hiding missing library dependencies by
# folding every math call into a constant. Exercise all six libm builtins.
printf '%s\n' 'PROGRAM maths; VAR x: REAL; BEGIN' \
  '  READ(x);' '  WRITELN(ROUND(SQRT(x + 4.0)));' \
  '  WRITELN(ROUND(SIN(x))); WRITELN(ROUND(COS(x)));' \
  '  WRITELN(ROUND(LN(x + 1.0))); WRITELN(ROUND(EXP(x)));' \
  '  WRITELN(ROUND(ARCTAN(x))) END.' > "$work/maths.pas"
printf '2\n0\n1\n0\n1\n0\n' > "$work/maths.out"
# Some fixtures never read stdin. A pipe races their exit against printf and
# can fail with SIGPIPE under pipefail; a regular input file has no writer.
printf '0\n' > "$work/input"
for dialect in vintage extended; do
  for opt in 0 1 2 3; do
    for src in "$work/maths.pas" tests/corpus/integration/builtin_lowercase_call.pas \
      tests/corpus/integration/nested_builtin_shadow_scope.pas; do
      label="$dialect $(basename "$src") O$opt"
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$src" -o "$work/exe" \
        > "$work/compile.out" 2> "$work/compile.err" || {
          cat "$work/compile.err" >&2; die "$label failed to link";
        }
      "$work/exe" < "$work/input" > "$work/output" 2> "$work/error" || {
        cat "$work/error" >&2; die "$label execution failed";
      }
      diff -u "${src%.pas}.out" "$work/output" || die "$label stdout"
      [[ ! -s $work/error ]] || die "$label stderr"
      pass "$label"
    done
  done
done
for opt in 0 1 2 3; do
  src=tests/corpus/golden/real32_builtins.pas
  bin/pascal1981 --dialect extended -O"$opt" "$src" -o "$work/exe" \
    > "$work/compile.out" 2> "$work/compile.err" || {
      cat "$work/compile.err" >&2; die "REAL32 builtins O$opt failed to link";
    }
  "$work/exe" > "$work/output" 2> "$work/error"
  diff -u "${src%.pas}.out" "$work/output" || die "REAL32 builtins O$opt stdout"
  [[ ! -s $work/error ]] || die "REAL32 builtins O$opt stderr"
  pass "REAL32 builtins O$opt"
done
finish 'Driver math linkage'
