#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# COPYSTR admits fixed-STRING copies and always checks capacity before writing.
# The check is error 2150, always caught (manual A-46): RANGECK does not
# control it. Only NVPTX keeps an unchecked boundary, inspected as IR only.
require bin/pascal1981 bin/parser bin/typechecker bin/codegen runtime/build/libpascalrt.a
cc=${CC:-clang}
for dialect in vintage extended; do
  for flag in + -; do
    cat > "$work/good.pas" <<EOF
PROGRAM good;
TYPE Five = STRING(5);
VAR d, e: Five; l: LSTRING(9); f: STRING(3); z: STRING(1); calls: INTEGER;
    a: ARRAY [1..2] OF STRING(2);
FUNCTION source: LSTRING(4);
BEGIN calls := calls + 1; source := 'xy' END;
PROCEDURE copyformal(CONST s: Five; VAR t: Five);
BEGIN COPYSTR(s, t) END;
BEGIN
  calls := 0;
  {\$RANGECK$flag}
  COPYSTR('ab', d); WRITELN('[', d, ']');
  COPYSTR('', d); WRITELN('[', d, ']');
  COPYSTR('q', z); WRITELN('[', z, ']');
  l := 'xyz'; COPYSTR(l, d); WRITELN('[', d, ']');
  f := 'pqr'; COPYSTR(f, d); WRITELN('[', d, ']');
  COPYSTR(source, d); WRITELN('[', d, ']', calls);
  a[2] := 'mn'; COPYSTR(a[2], d); WRITELN('[', d, ']');
  COPYSTR('abcde', d); WRITELN('[', d, ']');
  COPYSTR(d, d); WRITELN('[', d, ']');
  e := 'uv   '; copyformal(e, d); WRITELN('[', d, ']');
  IF FALSE THEN COPYSTR('overflow', d)
END.
EOF
    printf '%s\n' '[ab   ]' '[     ]' '[q]' '[xyz  ]' '[pqr  ]' '[xy   ]1' \
      '[mn   ]' '[abcde]' '[abcde]' '[uv   ]' > "$work/expected.out"
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/good.pas" -o "$work/good"
      "$work/good" > "$work/output" 2> "$work/error"
      diff -u "$work/expected.out" "$work/output"
      [[ ! -s $work/error ]] || die "$dialect valid COPYSTR RANGECK$flag O$opt stderr"
      pass "$dialect valid COPYSTR RANGECK$flag O$opt: blank fill, empty, exact, LSTRING/fixed/selected/function/formal, self"
    done
  done
  # Overflow is caught whatever the RANGECK setting, for literal, fixed and
  # LSTRING sources (whose current length, not capacity, is checked).
  for spec in "STRING(1) 'ab' 2 1" "STRING(3) s 4 3" "STRING(3) l 5 3" "STRING(300) big 301 300"; do
    read -r kind source length limit <<< "$spec"
    for flag in + -; do
      cat > "$work/bad.pas" <<EOF
PROGRAM bad;
VAR t: $kind; s: STRING(4); l: LSTRING(9); big: STRING(301); i: INTEGER;
BEGIN
  s := 'abcd'; l := 'abcde'; FOR i := 1 TO 301 DO big[i] := 'x';
  WRITELN('before');
  {\$RANGECK$flag}
  COPYSTR($source, t);
  WRITELN('wrong')
END.
EOF
      bin/pascal1981 --dialect "$dialect" -O0 -S "$work/bad.pas" -o "$work/bad.ll"
      [[ $(grep -c 'call void @pas_copystr_error' "$work/bad.ll" || true) == 1 ]] ||
        die "$dialect $kind COPYSTR RANGECK$flag guard count"
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
        rc=0
        { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        [[ $rc == 134 ]] || die "$dialect $kind COPYSTR RANGECK$flag O$opt exit $rc"
        printf 'before\n' > "$work/expected.out"
        printf 'runtime error: COPYSTR length %s exceeds capacity %s at line 7 column 3\n' \
          "$length" "$limit" > "$work/expected.err"
        diff -u "$work/expected.out" "$work/output"
        diff -u "$work/expected.err" "$work/error"
        pass "$dialect $kind COPYSTR($source) overflow under RANGECK$flag O$opt"
      done
    done
  done
  # Reject at typechecking, without producing output IR.
  for bad in 'COPYSTR(t)' 'COPYSTR(1, t)' 'COPYSTR(c, t)' 'COPYSTR(t, l)' \
      "COPYSTR(t, 'xx')" 'COPYSTR(t, a[1])' 'COPYSTR(t, source)' 'COPYSTR(t, missing)' \
      'COPYSTR(t, one)' 'COPYSTR(TRUE, t)' 'COPYSTR(t, t, t)' 'COPYSTR'; do
    cat > "$work/reject.pas" <<EOF
PROGRAM reject;
CONST one = 1;
VAR t: STRING(3); l: LSTRING(3); c: CHAR; a: ARRAY [1..2] OF STRING(3);
FUNCTION source: STRING(3); BEGIN source := 'abc' END;
BEGIN $bad END.
EOF
    if bin/pascal1981 --dialect "$dialect" -O0 -S "$work/reject.pas" -o "$work/reject.ll" 2> "$work/error"; then
      die "$dialect accepted invalid $bad"
    fi
    grep -q 'Type checking failed:' "$work/error" || die "$dialect late rejection: $bad"
    pass "$dialect typing rejects $bad"
  done
  # A user routine with the same name remains an ordinary call.
  printf '%s\n' 'PROGRAM shadow;' 'PROCEDURE COPYSTR(n: INTEGER); BEGIN WRITELN(n) END;' \
    'BEGIN COPYSTR(7) END.' > "$work/shadow.pas"
  bin/pascal1981 --dialect "$dialect" "$work/shadow.pas" -o "$work/shadow"
  "$work/shadow" > "$work/output"
  printf '7\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  pass "$dialect user COPYSTR shadowing"
done
# Observe the whole destination and neighbor through test-only abort wrapping,
# with RANGECK off. Test-only C observers require the extended dialect.
bin/pascal1981 --dialect extended -O0 -S tests/contract/fixtures/copystr_publication.pas -o "$work/publication.ll"
python3 tests/contract/fixtures/copystr_guard_order.py "$work/publication.ll"
for opt in 0 1 2 3; do
  "$cc" -O"$opt" "$work/publication.ll" tests/contract/fixtures/copystr_publication.c \
    runtime/build/libpascalrt.a -Wl,--wrap=abort -o "$work/publication"
  rc=0
  "$work/publication" > "$work/output" 2> "$work/error" || rc=$?
  [[ $rc == 134 ]] || die "COPYSTR publication O$opt exit $rc"
  printf 'PASS: COPYSTR destination and neighbor unchanged; source evaluated once\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  grep -qxF 'runtime error: COPYSTR length 4 exceeds capacity 3 at line 14 column 3' "$work/error"
  pass "COPYSTR failed publication and once-only source under RANGECK- O$opt"
done
# Negative control: the IR checker must reject a bypassed guard before any
# dangerous copy is executed. The mutation is applied only to scratch IR.
python3 - "$work/publication.ll" "$work/bypass.ll" <<'PY'
import re
import sys
from pathlib import Path
ir = Path(sys.argv[1]).read_text()
ir, n = re.subn(r'br i1 %copystr\.in\w*, label %copystr\.ok\w*, label %copystr\.bad\w*',
                'br label %copystr.ok', ir)
if n != 1:
    raise SystemExit('expected exactly one COPYSTR branch to mutate')
Path(sys.argv[2]).write_text(ir)
PY
if python3 tests/contract/fixtures/copystr_guard_order.py "$work/bypass.ll" > "$work/output" 2> "$work/error"; then
  die 'COPYSTR IR checker accepted bypassed guard'
fi
grep -q 'AssertionError: guard branch bypassed' "$work/error" || die 'COPYSTR IR negative control failed unexpectedly'
pass 'COPYSTR IR checker rejects bypassed guard (not executed)'
# Neither MATHCK nor RANGECK controls the check.
for mflag in + -; do
  for rflag in + -; do
    printf '%s\n' 'PROGRAM independent; VAR s: LSTRING(4); t: STRING(3);' \
      "BEGIN s := 'abcd'; {\$MATHCK$mflag}{\$RANGECK$rflag} COPYSTR(s, t) END." > "$work/independent.pas"
    bin/pascal1981 -O2 "$work/independent.pas" -o "$work/independent"
    rc=0
    { "$work/independent" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
    [[ $rc == 134 && ! -s $work/output ]] || die "COPYSTR MATHCK$mflag RANGECK$rflag exit/output $rc"
    grep -q '^runtime error: COPYSTR length 4 exceeds capacity 3 at line 2 column ' "$work/error"
    pass "COPYSTR caught under MATHCK$mflag RANGECK$rflag"
  done
done
# Legacy AST without check flags or coordinates still checks, reporting 0/0.
printf '%s\n' 'PROGRAM legacy; VAR t: STRING(3);' \
  'BEGIN COPYSTR('\''abcd'\'', t) END.' > "$work/legacy.pas"
bin/lexer < "$work/legacy.pas" | bin/parser | bin/typechecker > "$work/typed.json"
python3 - "$work/typed.json" "$work/legacy.json" <<'PY'
import json
import sys
from pathlib import Path

def strip(node):
    if isinstance(node, dict):
        return {k: strip(v) for k, v in node.items() if k not in ('rangeck', 'location')}
    if isinstance(node, list):
        return [strip(v) for v in node]
    return node

Path(sys.argv[2]).write_text(json.dumps(strip(json.loads(Path(sys.argv[1]).read_text()))))
PY
bin/codegen < "$work/legacy.json" > "$work/legacy.ll"
grep -qE 'call void @pas_copystr_error\(i64 [^,]+, i32 3, i32 0, i32 0\)' "$work/legacy.ll" || die 'legacy COPYSTR location'
pass 'legacy COPYSTR check and location'
# Untracked mutable string reads under INITCK+ must remain explicit boundaries.
for source in s 'source()'; do
  cat > "$work/initck.pas" <<EOF
PROGRAM boundary;
VAR s, t: STRING(4);
FUNCTION source: STRING(4); BEGIN source := 'abcd' END;
BEGIN s := 'abcd'; {\$INITCK+} COPYSTR($source, t) END.
EOF
  if bin/pascal1981 -O0 -S "$work/initck.pas" -o "$work/initck.ll" 2> "$work/error"; then die "COPYSTR INITCK accepted $source"; fi
  if [[ $source == s ]]; then
    grep -q 'INITCK unsupported boundary: global or captured storage' "$work/error" || die 'COPYSTR INITCK variable diagnostic'
  else
    grep -q 'INITCK unsupported boundary: STRING/LSTRING COPYSTR operand' "$work/error" || die 'COPYSTR INITCK function diagnostic'
  fi
  pass "COPYSTR explicit INITCK string boundary: $source"
done
printf '%s\n' 'PROGRAM literal; VAR t: STRING(4);' \
  'BEGIN {$INITCK+} COPYSTR('\''abcd'\'', t) END.' > "$work/literal.pas"
bin/pascal1981 -S "$work/literal.pas" -o "$work/literal.ll"
pass 'COPYSTR literal source needs no INITCK shadow'
# CPU DEVICE enforces the host contract; NVPTX retains the unchecked boundary.
printf '%s\n' 'DEVICE INTERFACE;' 'UNIT COPYU (check);' 'PROCEDURE check;' 'END;' > "$work/copy.inc"
printf '%s\n' '(*$INCLUDE:'\''copy.inc'\''*)' 'DEVICE IMPLEMENTATION OF COPYU;' \
  'PROCEDURE check;' 'VAR t: STRING(3);' "BEGIN COPYSTR('abcd', t) END;" '.' > "$work/copy.impl"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended -O0 -S copy.impl -o cpu.ll)
grep -q 'call void @pas_copystr_error' "$work/cpu.ll" || die 'CPU DEVICE COPYSTR guard'
pass 'CPU DEVICE COPYSTR guard'
printf '%s\n' '(*$INCLUDE:'\''copy.inc'\''*)' 'PROGRAM cpu;' 'USES COPYU (check);' \
  "BEGIN LAUNCH(check, 1, 1); WRITELN('wrong') END." > "$work/cpu.pas"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended cpu.pas copy.impl -o cpu)
rc=0
{ "$work/cpu" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
[[ $rc == 134 && ! -s $work/output ]] || die "CPU DEVICE COPYSTR exit/output $rc"
grep -qxF 'runtime error: COPYSTR length 4 exceeds capacity 3 at line 5 column 7' "$work/error"
pass 'CPU DEVICE COPYSTR runtime failure'
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended --device-triple nvptx64-nvidia-cuda -S copy.impl -o gpu.ll)
if grep -q 'pas_copystr_error' "$work/gpu.ll"; then die 'NVPTX emitted host COPYSTR failure'; fi
pass 'NVPTX existing unchecked COPYSTR boundary'
finish 'COPYSTR'
