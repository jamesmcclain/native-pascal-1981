#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# COPYLST admits string copies and checks capacity before copying or publishing length.
# Unchecked invalid copies are inspected as IR only, never executed.
require bin/pascal1981 bin/parser bin/typechecker bin/codegen runtime/build/libpascalrt.a
cc=${CC:-clang}
text200=$(printf '%200s' '' | tr ' ' a)
text55=$(printf '%55s' '' | tr ' ' b)
for dialect in vintage extended; do
  for flag in + -; do
    opposite=+; [[ $flag != + ]] || opposite=-
    cat > "$work/good.pas" <<EOF
PROGRAM good;
TYPE Small = LSTRING(4);
VAR t: Small; big: LSTRING(256); src: LSTRING(255); z: LSTRING(0);
    fixed: STRING(4); calls: INTEGER; a: ARRAY [1..2] OF Small;
FUNCTION source: Small;
BEGIN calls := calls + 1; source := 'xy' END;
PROCEDURE copyformal(CONST s: Small; VAR d: Small);
BEGIN COPYLST(s, d) END;
BEGIN
  calls := 0; t := 'abcd'; z := '';
  {\$RANGECK$flag}
  COPYLST('', z); COPYLST('', t); WRITELN(t);
  COPYLST('q', t); WRITELN(t);
  COPYLST({\$RANGECK$opposite} source, t);
  {\$RANGECK$flag}
  WRITELN(t); WRITELN(calls);
  COPYLST(t, t); WRITELN(t);
  fixed := 'pqrs'; COPYLST(fixed, t); WRITELN(t);
  a[1] := 'ab'; COPYLST(a[1], t); WRITELN(t);
  copyformal(t, a[2]); WRITELN(a[2]);
  src := '$text200'; CONCAT(src, '$text55'); COPYLST(src, src); COPYLST(src, big); WRITELN(big);
  IF FALSE THEN COPYLST('overflow', t)
END.
EOF
    printf '\nq\nxy\n1\nxy\npqrs\nab\nab\n%s%s\n' "$text200" "$text55" > "$work/expected.out"
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/good.pas" -o "$work/good"
      "$work/good" > "$work/output" 2> "$work/error"
      diff -u "$work/expected.out" "$work/output"
      [[ ! -s $work/error ]] || die "$dialect valid COPYLST$flag O$opt stderr"
      pass "$dialect valid COPYLST$flag O$opt: empty, char literal, self, fixed/selected/formal/function source, length 255"
    done
  done
  # Include capacity 0, exact+1, larger overflow, and a fixed source whose
  # length cannot fit the byte even when the destination has enough storage.
  for spec in '0 1 0' '3 4 3' '3 8 3' '255 256 255' '256 256 255' 'bare 256 255'; do
    read -r cap length limit <<< "$spec"
    kind="LSTRING($cap)"; [[ $cap != bare ]] || kind=LSTRING
    for flag in + -; do
      opposite=+; [[ $flag != + ]] || opposite=-
      cat > "$work/bad.pas" <<EOF
PROGRAM bad;
VAR s: STRING($length); t: $kind; i: INTEGER;
BEGIN
  FOR i := 1 TO $length DO s[i] := 'x'; t := '';
  WRITELN('before');
  {\$RANGECK$flag}
  COPYLST({\$RANGECK$opposite} s, t);
  WRITELN('wrong')
END.
EOF
      bin/pascal1981 --dialect "$dialect" -O0 -S "$work/bad.pas" -o "$work/bad.ll"
      expected=0; [[ $flag != + ]] || expected=1
      [[ $(grep -c 'call void @pas_copylst_error' "$work/bad.ll" || true) == "$expected" ]] || die "$dialect capacity $cap COPYLST$flag guards"
      if [[ $flag == - ]]; then
        pass "$dialect capacity $cap disabled COPYLST guard-free IR (not executed)"
        continue
      fi
      # LLVM folds this fixed source's wide compare; dynamic ordering is
      # checked separately with the function-result publication fixture.
      grep -q 'br i1 false, label %copylst.ok, label %copylst.bad' "$work/bad.ll" || die 'COPYLST fixed overflow branch'
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
        rc=0
        { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        [[ $rc == 134 ]] || die "$dialect capacity $cap COPYLST O$opt exit $rc"
        printf 'before\n' > "$work/expected.out"
        printf 'runtime error: RANGECK COPYLST length %s exceeds capacity %s at line 7 column 3\n' "$length" "$limit" > "$work/expected.err"
        diff -u "$work/expected.out" "$work/output"
        diff -u "$work/expected.err" "$work/error"
        pass "$dialect capacity $cap COPYLST overflow O$opt"
      done
    done
  done
  # Reject at typechecking, without producing output IR.
  for bad in 'COPYLST(t)' 'COPYLST(1, t)' 'COPYLST(c, t)' 'COPYLST(t, fixed)' \
      "COPYLST(t, 'xx')" 'COPYLST(t, a[1])' 'COPYLST(t, source)' 'COPYLST(t, missing)' \
      'COPYLST(t, one)' 'COPYLST(TRUE, t)' 'COPYLST(t, t, t)' 'COPYLST'; do
    cat > "$work/reject.pas" <<EOF
PROGRAM reject;
CONST one = 1;
VAR t: LSTRING(3); fixed: STRING(3); c: CHAR; a: ARRAY [1..2] OF LSTRING(3);
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
  printf '%s\n' 'PROGRAM shadow;' 'PROCEDURE COPYLST(n: INTEGER); BEGIN WRITELN(n) END;' \
    'BEGIN COPYLST(7) END.' > "$work/shadow.pas"
  bin/pascal1981 --dialect "$dialect" "$work/shadow.pas" -o "$work/shadow"
  "$work/shadow" > "$work/output"
  printf '7\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  pass "$dialect user COPYLST shadowing"
done
# Observe the whole destination and neighbor through test-only abort wrapping.
# Dynamic function length prevents a constant-folded check masking ordering.
# Test-only C observers require the extended dialect.
for dialect in extended; do
  bin/pascal1981 --dialect "$dialect" -O0 -S tests/contract/fixtures/copylst_publication.pas -o "$work/publication.ll"
  python3 tests/contract/fixtures/copylst_guard_order.py "$work/publication.ll"
  for opt in 0 1 2 3; do
    "$cc" -O"$opt" "$work/publication.ll" tests/contract/fixtures/copylst_publication.c \
      runtime/build/libpascalrt.a -Wl,--wrap=abort -o "$work/publication"
    rc=0
    "$work/publication" > "$work/output" 2> "$work/error" || rc=$?
    [[ $rc == 134 ]] || die "$dialect COPYLST publication O$opt exit $rc"
    printf 'PASS: COPYLST destination and neighbor unchanged; source evaluated once\n' > "$work/expected.out"
    diff -u "$work/expected.out" "$work/output"
    grep -qxF 'runtime error: RANGECK COPYLST length 4 exceeds capacity 3 at line 15 column 3' "$work/error"
    pass "$dialect COPYLST failed publication and once-only source O$opt"
  done
done
# Negative control: the IR checker must reject a bypassed guard before any
# dangerous copy is executed. The mutation is applied only to scratch IR.
python3 - "$work/publication.ll" "$work/bypass.ll" <<'PY'
import re
import sys
from pathlib import Path
ir = Path(sys.argv[1]).read_text()
ir, n = re.subn(r'br i1 %copylst\.in\w*, label %copylst\.ok\w*, label %copylst\.bad\w*',
                'br label %copylst.ok', ir)
if n != 1:
    raise SystemExit('expected exactly one COPYLST branch to mutate')
Path(sys.argv[2]).write_text(ir)
PY
if python3 tests/contract/fixtures/copylst_guard_order.py "$work/bypass.ll" > "$work/output" 2> "$work/error"; then
  die 'COPYLST IR checker accepted bypassed guard'
fi
grep -q 'AssertionError: guard branch bypassed' "$work/error" || die 'COPYLST IR negative control failed unexpectedly'
pass 'COPYLST IR checker rejects bypassed guard (not executed)'
# RANGECK enforcement is independent of MATHCK, including dynamic lengths.
for flag in + -; do
  printf '%s\n' 'PROGRAM independent; VAR s: LSTRING(4); t: LSTRING(3);' \
    "BEGIN s := 'abcd'; {\$MATHCK$flag}{\$RANGECK+} COPYLST(s, t) END." > "$work/independent.pas"
  for opt in 0 1 2 3; do
    bin/pascal1981 -O"$opt" "$work/independent.pas" -o "$work/independent"
    rc=0
    { "$work/independent" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
    [[ $rc == 134 && ! -s $work/output ]] || die "COPYLST MATHCK$flag O$opt exit/output $rc"
    grep -q '^runtime error: RANGECK COPYLST length 4 exceeds capacity 3 at line 2 column ' "$work/error"
    pass "COPYLST RANGECK independent of MATHCK$flag O$opt"
  done
done
# Nested/sibling first-token snapshots; malformed unchecked copies not run.
printf '%s\n' 'PROGRAM snapshots; VAR t: LSTRING(3);' 'BEGIN t := '\''ab'\'';' \
  '  {$RANGECK+}' '  IF TRUE THEN BEGIN {$RANGECK-} COPYLST('\''abcd'\'', t) END;' \
  '  {$RANGECK+}' '  COPYLST({$RANGECK-} '\''abcd'\'', t);' \
  '  COPYLST({$RANGECK+} '\''abcd'\'', t)' 'END.' > "$work/snapshots.pas"
bin/pascal1981 -O0 -S "$work/snapshots.pas" -o "$work/snapshots.ll"
[[ $(grep -c 'call void @pas_copylst_error' "$work/snapshots.ll") == 1 ]] || die 'COPYLST nested/sibling snapshots'
pass 'COPYLST nested/sibling first-token snapshots'
# Legacy AST inherits enabled policy and reports missing coordinates as 0/0.
printf '%s\n' 'PROGRAM legacy; VAR t: LSTRING(3);' \
  'BEGIN COPYLST('\''abcd'\'', t) END.' > "$work/legacy.pas"
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
grep -qE 'call void @pas_copylst_error\(i64 [^,]+, i32 3, i32 0, i32 0\)' "$work/legacy.ll" || die 'legacy COPYLST policy/location'
pass 'legacy COPYLST policy and location'
# Untracked mutable string reads under INITCK+ must remain explicit boundaries.
for source in s 'source()'; do
  cat > "$work/initck.pas" <<EOF
PROGRAM boundary;
VAR s, t: LSTRING(4);
FUNCTION source: LSTRING(4); BEGIN source := 'abcd' END;
BEGIN s := 'abcd'; {\$INITCK+} COPYLST($source, t) END.
EOF
  if bin/pascal1981 -O0 -S "$work/initck.pas" -o "$work/initck.ll" 2> "$work/error"; then die "COPYLST INITCK accepted $source"; fi
  if [[ $source == s ]]; then
    grep -q 'INITCK unsupported boundary: global or captured storage' "$work/error" || die 'COPYLST INITCK variable diagnostic'
  else
    grep -q 'INITCK unsupported boundary: STRING/LSTRING COPYLST operand' "$work/error" || die 'COPYLST INITCK function diagnostic'
  fi
  pass "COPYLST explicit INITCK string boundary: $source"
done
printf '%s\n' 'PROGRAM literal; VAR t: LSTRING(4);' \
  'BEGIN {$INITCK+} COPYLST('\''abcd'\'', t) END.' > "$work/literal.pas"
bin/pascal1981 -S "$work/literal.pas" -o "$work/literal.ll"
pass 'COPYLST literal source needs no INITCK shadow'
# CPU DEVICE enforces the host contract; NVPTX retains the unchecked boundary.
printf '%s\n' 'DEVICE INTERFACE;' 'UNIT COPYU (check);' 'PROCEDURE check;' 'END;' > "$work/copy.inc"
printf '%s\n' '(*$INCLUDE:'\''copy.inc'\''*)' 'DEVICE IMPLEMENTATION OF COPYU;' \
  'PROCEDURE check;' 'VAR t: LSTRING(3);' "BEGIN COPYLST('abcd', t) END;" '.' > "$work/copy.impl"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended -O0 -S copy.impl -o cpu.ll)
grep -q 'call void @pas_copylst_error' "$work/cpu.ll" || die 'CPU DEVICE COPYLST guard'
pass 'CPU DEVICE COPYLST guard'
printf '%s\n' '(*$INCLUDE:'\''copy.inc'\''*)' 'PROGRAM cpu;' 'USES COPYU (check);' \
  "BEGIN LAUNCH(check, 1, 1); WRITELN('wrong') END." > "$work/cpu.pas"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended cpu.pas copy.impl -o cpu)
rc=0
{ "$work/cpu" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
[[ $rc == 134 && ! -s $work/output ]] || die "CPU DEVICE COPYLST exit/output $rc"
grep -qxF 'runtime error: RANGECK COPYLST length 4 exceeds capacity 3 at line 5 column 7' "$work/error"
pass 'CPU DEVICE COPYLST runtime failure'
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended --device-triple nvptx64-nvidia-cuda -S copy.impl -o gpu.ll)
if grep -q 'pas_copylst_error' "$work/gpu.ll"; then die 'NVPTX emitted host COPYLST failure'; fi
pass 'NVPTX existing unchecked COPYLST boundary'
finish 'RANGECK COPYLST'
