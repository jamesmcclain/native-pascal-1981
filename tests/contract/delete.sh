#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# DELETE admits LSTRING deletions and always checks the span before writing.
# A span past the length is error 2151, always caught (manual A-46): RANGECK
# does not control it. A position below 1 or a negative count fails the same
# check. Only NVPTX keeps an unchecked boundary, inspected as IR only.
require bin/pascal1981 bin/parser bin/typechecker bin/codegen runtime/build/libpascalrt.a
cc=${CC:-clang}
for dialect in vintage extended; do
  for flag in + -; do
    cat > "$work/good.pas" <<EOF
PROGRAM good;
TYPE Nine = LSTRING(9); Small = 0..9;
VAR d: Nine; e: LSTRING(0); calls: INTEGER; k: Small;
FUNCTION two: INTEGER;
BEGIN calls := calls + 1; d := 'uvwxyz'; two := 2 END;
PROCEDURE cut(VAR t: Nine; i: INTEGER);
BEGIN DELETE(t, i, 1) END;
BEGIN
  calls := 0;
  {\$RANGECK$flag}
  d := 'abcdef'; DELETE(d, 2, 3); WRITELN('[', d, ']');
  d := 'abcdef'; DELETE(d, 1, 6); WRITELN('[', d, ']');
  d := 'abcdef'; DELETE(d, 7, 0); WRITELN('[', d, ']');
  d := 'abcdef'; DELETE(d, 6, 1); WRITELN('[', d, ']');
  d := 'abcdef'; DELETE(d, 3, 0); WRITELN('[', d, ']');
  e := ''; DELETE(e, 1, 0); WRITELN('[', e, ']');
  d := 'abc'; DELETE(d, 1, two); WRITELN('[', d, ']', calls);
  d := 'abcdef'; k := 4; DELETE(d, k - 2, k - 1); WRITELN('[', d, ']');
  d := 'abcdef'; cut(d, 4); WRITELN('[', d, ']');
  IF FALSE THEN DELETE(d, 9, 9)
END.
EOF
    printf '%s\n' '[aef]' '[]' '[abcdef]' '[abcde]' '[abcdef]' '[]' '[wxyz]1' \
      '[aef]' '[abcef]' > "$work/expected.out"
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/good.pas" -o "$work/good"
      "$work/good" > "$work/output" 2> "$work/error"
      diff -u "$work/expected.out" "$work/output"
      [[ ! -s $work/error ]] || die "$dialect valid DELETE RANGECK$flag O$opt stderr"
      pass "$dialect valid DELETE RANGECK$flag O$opt: middle, whole, empty at end, last, zero count, length read after actuals, formal"
    done
  done
  # Each invalid span is caught whatever the RANGECK setting.
  for spec in '5 3 6' '0 1 6' '-1 2 6' '2 -1 6' '8 0 6' '1 1 0' '32767 32767 6' '-32768 1 6'; do
    read -r pos count len <<< "$spec"
    for flag in + -; do
      cat > "$work/bad.pas" <<EOF
PROGRAM bad;
VAR t: LSTRING(9); i, n: INTEGER;
BEGIN
  t := 'abcdefgh'; t.LEN := CHR($len); i := $pos; n := $count;
  WRITELN('before');
  {\$RANGECK$flag}
  DELETE(t, i, n);
  WRITELN('wrong')
END.
EOF
      bin/pascal1981 --dialect "$dialect" -O0 -S "$work/bad.pas" -o "$work/bad.ll"
      [[ $(grep -c 'call void @pas_delete_error' "$work/bad.ll" || true) == 1 ]] ||
        die "$dialect DELETE($pos, $count) RANGECK$flag guard count"
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
        rc=0
        { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        [[ $rc == 134 ]] || die "$dialect DELETE($pos, $count) RANGECK$flag O$opt exit $rc"
        printf 'before\n' > "$work/expected.out"
        printf 'runtime error: DELETE position %s count %s is outside length %s at line 7 column 3\n' \
          "$pos" "$count" "$len" > "$work/expected.err"
        diff -u "$work/expected.out" "$work/output"
        diff -u "$work/expected.err" "$work/error"
        pass "$dialect DELETE position $pos count $count length $len caught under RANGECK$flag O$opt"
      done
    done
  done
  # Reject at typechecking, without producing output IR.
  for bad in 'DELETE(t, 1)' 'DELETE(f, 1, 1)' "DELETE('abc', 1, 1)" 'DELETE(a[1], 1, 1)' \
      'DELETE(source, 1, 1)' 'DELETE(missing, 1, 1)' 'DELETE(one, 1, 1)' "DELETE(t, 'a', 1)" \
      'DELETE(t, 1, 1.0)' 'DELETE(t, TRUE, 1)' 'DELETE(t, 1, 1, 1)' 'DELETE'; do
    cat > "$work/reject.pas" <<EOF
PROGRAM reject;
CONST one = 1;
VAR t: LSTRING(3); f: STRING(3); a: ARRAY [1..2] OF LSTRING(3);
FUNCTION source: LSTRING(3); BEGIN source := 'abc' END;
BEGIN $bad END.
EOF
    if bin/pascal1981 --dialect "$dialect" -O0 -S "$work/reject.pas" -o "$work/reject.ll" 2> "$work/error"; then
      die "$dialect accepted invalid $bad"
    fi
    grep -q 'Type checking failed:' "$work/error" || die "$dialect late rejection: $bad"
    pass "$dialect typing rejects $bad"
  done
  # A user routine with the same name remains an ordinary call.
  printf '%s\n' 'PROGRAM shadow;' 'PROCEDURE DELETE(n: INTEGER); BEGIN WRITELN(n) END;' \
    'BEGIN DELETE(7) END.' > "$work/shadow.pas"
  bin/pascal1981 --dialect "$dialect" "$work/shadow.pas" -o "$work/shadow"
  "$work/shadow" > "$work/output"
  printf '7\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  pass "$dialect user DELETE shadowing"
done
# Observe the whole destination and neighbor through test-only abort wrapping,
# with RANGECK off. Test-only C observers require the extended dialect.
bin/pascal1981 --dialect extended -O0 -S tests/contract/fixtures/delete_publication.pas -o "$work/publication.ll"
python3 tests/contract/fixtures/delete_guard_order.py "$work/publication.ll"
for opt in 0 1 2 3; do
  "$cc" -O"$opt" "$work/publication.ll" tests/contract/fixtures/delete_publication.c \
    runtime/build/libpascalrt.a -Wl,--wrap=abort -o "$work/publication"
  rc=0
  "$work/publication" > "$work/output" 2> "$work/error" || rc=$?
  [[ $rc == 134 ]] || die "DELETE publication O$opt exit $rc"
  printf 'PASS: DELETE destination and neighbor unchanged; count evaluated once\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  grep -qxF 'runtime error: DELETE position 3 count 3 is outside length 4 at line 14 column 3' "$work/error"
  pass "DELETE failed publication and once-only count under RANGECK- O$opt"
done
# Negative control: the IR checker must reject a bypassed guard before any
# dangerous move is executed. The mutation is applied only to scratch IR.
python3 - "$work/publication.ll" "$work/bypass.ll" <<'PY'
import re
import sys
from pathlib import Path
ir = Path(sys.argv[1]).read_text()
ir, n = re.subn(r'br i1 %delete\.in\w*, label %delete\.ok\w*, label %delete\.bad\w*',
                'br label %delete.ok', ir)
if n != 1:
    raise SystemExit('expected exactly one DELETE branch to mutate')
Path(sys.argv[2]).write_text(ir)
PY
if python3 tests/contract/fixtures/delete_guard_order.py "$work/bypass.ll" > "$work/output" 2> "$work/error"; then
  die 'DELETE IR checker accepted bypassed guard'
fi
grep -q 'AssertionError: guard branch bypassed' "$work/error" || die 'DELETE IR negative control failed unexpectedly'
pass 'DELETE IR checker rejects bypassed guard (not executed)'
# Neither MATHCK nor RANGECK controls the check.
for mflag in + -; do
  for rflag in + -; do
    printf '%s\n' 'PROGRAM independent; VAR t: LSTRING(4); i: INTEGER;' \
      "BEGIN t := 'abcd'; i := 4; {\$MATHCK$mflag}{\$RANGECK$rflag} DELETE(t, i, 2) END." > "$work/independent.pas"
    bin/pascal1981 -O2 "$work/independent.pas" -o "$work/independent"
    rc=0
    { "$work/independent" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
    [[ $rc == 134 && ! -s $work/output ]] || die "DELETE MATHCK$mflag RANGECK$rflag exit/output $rc"
    grep -q '^runtime error: DELETE position 4 count 2 is outside length 4 at line 2 column ' "$work/error"
    pass "DELETE caught under MATHCK$mflag RANGECK$rflag"
  done
done
# Legacy AST without check flags or coordinates still checks, reporting 0/0.
printf '%s\n' 'PROGRAM legacy; VAR t: LSTRING(3);' \
  'BEGIN t := '\''abc'\''; DELETE(t, 3, 2) END.' > "$work/legacy.pas"
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
grep -qE 'call void @pas_delete_error\(i32 [^,]+, i32 [^,]+, i32 [^,]+, i32 0, i32 0\)' "$work/legacy.ll" || die 'legacy DELETE location'
pass 'legacy DELETE check and location'
# Untracked string destinations under INITCK+ remain explicit boundaries.
printf '%s\n' 'PROGRAM boundary; VAR d: LSTRING(5);' \
  "BEGIN d := 'abc'; {\$INITCK+} DELETE(d, 1, 1) END." > "$work/initck.pas"
if bin/pascal1981 -O0 -S "$work/initck.pas" -o "$work/initck.ll" 2> "$work/error"; then die 'DELETE INITCK accepted global'; fi
grep -q 'INITCK unsupported boundary: global or captured storage' "$work/error" || die 'DELETE INITCK global diagnostic'
pass 'DELETE explicit INITCK boundary: global destination'
printf '%s\n' 'PROGRAM boundary;' 'PROCEDURE p;' 'VAR d: LSTRING(5);' \
  "BEGIN d := 'abc'; {\$INITCK+} DELETE(d, 1, 1) END;" 'BEGIN p END.' > "$work/initck.pas"
if bin/pascal1981 -O0 -S "$work/initck.pas" -o "$work/initck.ll" 2> "$work/error"; then die 'DELETE INITCK accepted local'; fi
grep -q 'INITCK unsupported boundary: untracked type' "$work/error" || die 'DELETE INITCK local diagnostic'
pass 'DELETE explicit INITCK boundary: local destination'
# CPU DEVICE enforces the host contract; NVPTX retains the unchecked boundary.
printf '%s\n' 'DEVICE INTERFACE;' 'UNIT DELU (check);' 'PROCEDURE check;' 'END;' > "$work/del.inc"
printf '%s\n' '(*$INCLUDE:'\''del.inc'\''*)' 'DEVICE IMPLEMENTATION OF DELU;' \
  'PROCEDURE check;' 'VAR t: LSTRING(3);' "BEGIN t := 'abc'; DELETE(t, 3, 2) END;" '.' > "$work/del.impl"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended -O0 -S del.impl -o cpu.ll)
grep -q 'call void @pas_delete_error' "$work/cpu.ll" || die 'CPU DEVICE DELETE guard'
pass 'CPU DEVICE DELETE guard'
printf '%s\n' '(*$INCLUDE:'\''del.inc'\''*)' 'PROGRAM cpu;' 'USES DELU (check);' \
  "BEGIN LAUNCH(check, 1, 1); WRITELN('wrong') END." > "$work/cpu.pas"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended cpu.pas del.impl -o cpu)
rc=0
{ "$work/cpu" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
[[ $rc == 134 && ! -s $work/output ]] || die "CPU DEVICE DELETE exit/output $rc"
grep -qxF 'runtime error: DELETE position 3 count 2 is outside length 3 at line 5 column 19' "$work/error"
pass 'CPU DEVICE DELETE runtime failure'
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended --device-triple nvptx64-nvidia-cuda -S del.impl -o gpu.ll)
if grep -q 'pas_delete_error' "$work/gpu.ll"; then die 'NVPTX emitted host DELETE failure'; fi
pass 'NVPTX existing unchecked DELETE boundary'
finish 'DELETE'
