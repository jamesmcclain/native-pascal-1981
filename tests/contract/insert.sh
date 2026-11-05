#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# INSERT admits LSTRING insertions and always checks position and capacity first.
# Both failures are error 2151, always caught (manual A-46): RANGECK does not
# control them. Positions 1..length + 1 are valid; the manual's text forbids
# length + 1, a deliberate difference. Only NVPTX keeps an unchecked boundary.
require bin/pascal1981 bin/parser bin/typechecker bin/codegen runtime/build/libpascalrt.a
cc=${CC:-clang}
text200=$(printf '%200s' '' | tr ' ' a)
text55=$(printf '%55s' '' | tr ' ' b)
for dialect in vintage extended; do
  for flag in + -; do
    cat > "$work/good.pas" <<EOF
PROGRAM good;
TYPE Nine = LSTRING(9); Small = 0..9;
VAR d, d2: Nine; e: LSTRING(4); f: STRING(2); big: LSTRING(256); calls: INTEGER;
    k: Small; a: ARRAY [1..2] OF LSTRING(2);
FUNCTION three: INTEGER;
BEGIN calls := calls + 1; d := 'uvw'; three := 3 END;
FUNCTION source: LSTRING(4);
BEGIN calls := calls + 1; source := 'xy' END;
PROCEDURE put(CONST s: Nine; VAR t: Nine);
BEGIN INSERT(s, t, 1) END;
BEGIN
  calls := 0;
  {\$RANGECK$flag}
  d := 'abef'; INSERT('cd', d, 3); WRITELN('[', d, ']');
  d := 'bc'; INSERT('a', d, 1); WRITELN('[', d, ']');
  d := 'ab'; INSERT('cd', d, 3); WRITELN('[', d, ']');
  d := ''; INSERT('xyz', d, 1); WRITELN('[', d, ']');
  d := 'abc'; INSERT(d, d, 2); WRITELN('[', d, ']');
  d := 'abc'; INSERT(d, d, 1); WRITELN('[', d, ']');
  d := 'abc'; INSERT(d, d, 4); WRITELN('[', d, ']');
  d := 'abc'; put(d, d); WRITELN('[', d, ']');
  d := 'abc'; INSERT('', d, 4); WRITELN('[', d, ']');
  e := 'abc'; INSERT('d', e, 4); WRITELN('[', e, ']');
  d := 'abc'; f := 'pq'; INSERT(f, d, 2); WRITELN('[', d, ']');
  d := 'abc'; a[2] := 'mn'; INSERT(a[2], d, 4); WRITELN('[', d, ']');
  d := 'abc'; INSERT('-', d, three); WRITELN('[', d, ']', calls);
  d := 'ab'; INSERT(source, d, 2); WRITELN('[', d, ']', calls);
  d := 'abcd'; k := 2; INSERT('z', d, k + 1); WRITELN('[', d, ']');
  d := 'cd'; d2 := 'ab'; put(d2, d); WRITELN('[', d, ']');
  big := '$text200'; INSERT('$text55', big, 201); WRITELN(big);
  IF FALSE THEN INSERT('overflow', e, 9)
END.
EOF
    printf '%s\n' '[abcdef]' '[abc]' '[abcd]' '[xyz]' '[aabcbc]' '[abcabc]' '[abcabc]' '[abcabc]' '[abc]' '[abcd]' \
      '[apqbc]' '[abcmn]' '[uv-w]1' '[axyb]2' '[abzcd]' '[abcd]' "$text200$text55" \
      > "$work/expected.out"
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/good.pas" -o "$work/good"
      "$work/good" > "$work/output" 2> "$work/error"
      diff -u "$work/expected.out" "$work/output"
      [[ ! -s $work/error ]] || die "$dialect valid INSERT RANGECK$flag O$opt stderr"
      pass "$dialect valid INSERT RANGECK$flag O$opt: middle, front, append, empty, self, exact capacity, length read after actuals, length 255"
    done
  done
  # Each invalid position is caught whatever the RANGECK setting.
  for spec in '0 3' '-1 3' '5 3' '2 0' '32767 3' '-32768 3'; do
    read -r pos len <<< "$spec"
    for flag in + -; do
      cat > "$work/bad.pas" <<EOF
PROGRAM bad;
VAR t: LSTRING(9); i: INTEGER;
BEGIN
  t := 'abcdefgh'; t.LEN := CHR($len); i := $pos;
  WRITELN('before');
  {\$RANGECK$flag}
  INSERT('x', t, i);
  WRITELN('wrong')
END.
EOF
      bin/pascal1981 --dialect "$dialect" -O0 -S "$work/bad.pas" -o "$work/bad.ll"
      [[ $(grep -c 'call void @pas_insert_position_error' "$work/bad.ll" || true) == 1 ]] ||
        die "$dialect INSERT position $pos RANGECK$flag guard count"
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
        rc=0
        { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        [[ $rc == 134 ]] || die "$dialect INSERT position $pos RANGECK$flag O$opt exit $rc"
        printf 'before\n' > "$work/expected.out"
        printf 'runtime error: INSERT position %s is outside 1..%s at line 7 column 3\n' \
          "$pos" "$((len + 1))" > "$work/expected.err"
        diff -u "$work/expected.out" "$work/output"
        diff -u "$work/expected.err" "$work/error"
        pass "$dialect INSERT position $pos length $len caught under RANGECK$flag O$opt"
      done
    done
  done
  # Capacity overflow, including a length that cannot fit the length byte
  # even when the destination has enough storage.
  for spec in "LSTRING(0) 'x' 0 1 0" "LSTRING(4) 'xyz' 3 6 4" "LSTRING(4) s 3 7 4" \
      "LSTRING(256) big 255 256 255" "LSTRING 'x' 255 256 255"; do
    read -r kind source init length limit <<< "$spec"
    for flag in + -; do
      cat > "$work/bad.pas" <<EOF
PROGRAM bad;
VAR t: $kind; s: STRING(4); big: LSTRING(256); i: INTEGER;
BEGIN
  s := 'abcd'; t := ''; FOR i := 1 TO $init DO CONCAT(t, 'a');
  big := ''; CONCAT(big, 'z');
  WRITELN('before');
  {\$RANGECK$flag}
  INSERT($source, t, 1);
  WRITELN('wrong')
END.
EOF
      bin/pascal1981 --dialect "$dialect" -O0 -S "$work/bad.pas" -o "$work/bad.ll"
      [[ $(grep -c 'call void @pas_insert_error' "$work/bad.ll" || true) == 1 ]] ||
        die "$dialect $kind INSERT capacity RANGECK$flag guard count"
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
        rc=0
        { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        [[ $rc == 134 ]] || die "$dialect $kind INSERT capacity RANGECK$flag O$opt exit $rc"
        printf 'before\n' > "$work/expected.out"
        printf 'runtime error: INSERT length %s exceeds capacity %s at line 8 column 3\n' \
          "$length" "$limit" > "$work/expected.err"
        diff -u "$work/expected.out" "$work/output"
        diff -u "$work/expected.err" "$work/error"
        pass "$dialect $kind INSERT($source) capacity caught under RANGECK$flag O$opt"
      done
    done
  done
  # Reject at typechecking, without producing output IR.
  for bad in "INSERT('a', t)" "INSERT('a', f, 1)" "INSERT('a', 'abc', 1)" "INSERT('a', a[1], 1)" \
      "INSERT('a', source, 1)" "INSERT('a', missing, 1)" "INSERT('a', one, 1)" "INSERT(c, t, 1)" \
      "INSERT(1, t, 1)" "INSERT('a', t, 'b')" "INSERT('a', t, 1.0)" "INSERT('a', t, 1, 1)" 'INSERT'; do
    cat > "$work/reject.pas" <<EOF
PROGRAM reject;
CONST one = 1;
VAR t: LSTRING(3); f: STRING(3); c: CHAR; a: ARRAY [1..2] OF LSTRING(3);
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
  printf '%s\n' 'PROGRAM shadow;' 'PROCEDURE INSERT(n: INTEGER); BEGIN WRITELN(n) END;' \
    'BEGIN INSERT(7) END.' > "$work/shadow.pas"
  bin/pascal1981 --dialect "$dialect" "$work/shadow.pas" -o "$work/shadow"
  "$work/shadow" > "$work/output"
  printf '7\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  pass "$dialect user INSERT shadowing"
done
# Observe the whole destination and neighbor through test-only abort wrapping,
# with RANGECK off. Test-only C observers require the extended dialect.
bin/pascal1981 --dialect extended -O0 -S tests/contract/fixtures/insert_publication.pas -o "$work/publication.ll"
python3 tests/contract/fixtures/insert_guard_order.py "$work/publication.ll"
for opt in 0 1 2 3; do
  "$cc" -O"$opt" "$work/publication.ll" tests/contract/fixtures/insert_publication.c \
    runtime/build/libpascalrt.a -Wl,--wrap=abort -o "$work/publication"
  rc=0
  "$work/publication" > "$work/output" 2> "$work/error" || rc=$?
  [[ $rc == 134 ]] || die "INSERT publication O$opt exit $rc"
  printf 'PASS: INSERT destination and neighbor unchanged; source evaluated once\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  grep -qxF 'runtime error: INSERT length 7 exceeds capacity 5 at line 14 column 3' "$work/error"
  pass "INSERT failed publication and once-only source under RANGECK- O$opt"
done
# Negative controls: the IR checker must reject either bypassed guard before
# any dangerous move is executed. Mutations are applied only to scratch IR.
for prefix in insertpos insert; do
  python3 - "$work/publication.ll" "$work/bypass.ll" "$prefix" <<'PY'
import re
import sys
from pathlib import Path
ir = Path(sys.argv[1]).read_text()
p = sys.argv[3]
ir, n = re.subn(r'br i1 %%%s\.in\w*, label %%%s\.ok\w*, label %%%s\.bad\w*' % (p, p, p),
                'br label %%%s.ok' % p, ir)
if n != 1:
    raise SystemExit('expected exactly one %s branch to mutate' % p)
Path(sys.argv[2]).write_text(ir)
PY
  if python3 tests/contract/fixtures/insert_guard_order.py "$work/bypass.ll" > "$work/output" 2> "$work/error"; then
    die "INSERT IR checker accepted bypassed $prefix guard"
  fi
  grep -q 'AssertionError: guard branch bypassed' "$work/error" || die "INSERT $prefix negative control failed unexpectedly"
  pass "INSERT IR checker rejects bypassed $prefix guard (not executed)"
done
# Neither MATHCK nor RANGECK controls the checks.
for mflag in + -; do
  for rflag in + -; do
    printf '%s\n' 'PROGRAM independent; VAR t: LSTRING(4); i: INTEGER;' \
      "BEGIN t := 'abc'; i := 5; {\$MATHCK$mflag}{\$RANGECK$rflag} INSERT('x', t, i) END." > "$work/independent.pas"
    bin/pascal1981 -O2 "$work/independent.pas" -o "$work/independent"
    rc=0
    { "$work/independent" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
    [[ $rc == 134 && ! -s $work/output ]] || die "INSERT MATHCK$mflag RANGECK$rflag exit/output $rc"
    grep -q '^runtime error: INSERT position 5 is outside 1..4 at line 2 column ' "$work/error"
    pass "INSERT caught under MATHCK$mflag RANGECK$rflag"
  done
done
# Legacy AST without check flags or coordinates still checks, reporting 0/0.
printf '%s\n' 'PROGRAM legacy; VAR t: LSTRING(3);' \
  'BEGIN t := '\''abc'\''; INSERT('\''x'\'', t, 1) END.' > "$work/legacy.pas"
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
grep -qE 'call void @pas_insert_error\(i64 [^,]+, i32 3, i32 0, i32 0\)' "$work/legacy.ll" || die 'legacy INSERT capacity location'
grep -qE 'call void @pas_insert_position_error\(i32 [^,]+, i32 0, i32 [^,]+, i32 0, i32 0\)' "$work/legacy.ll" || die 'legacy INSERT position location'
pass 'legacy INSERT checks and locations'
# Untracked mutable string reads under INITCK+ must remain explicit boundaries.
# INSERT reads its destination too, so INITCK is scoped to the source here;
# the destination boundary is checked separately below.
for source in s 'source()'; do
  cat > "$work/initck.pas" <<EOF
PROGRAM boundary;
VAR s, t: LSTRING(4);
FUNCTION source: LSTRING(4); BEGIN source := 'ab' END;
BEGIN s := 'ab'; INSERT({\$INITCK+} $source, {\$INITCK-} t, 1) END.
EOF
  if bin/pascal1981 -O0 -S "$work/initck.pas" -o "$work/initck.ll" 2> "$work/error"; then die "INSERT INITCK accepted $source"; fi
  if [[ $source == s ]]; then
    grep -q 'INITCK unsupported boundary: global or captured storage' "$work/error" || die 'INSERT INITCK variable diagnostic'
  else
    grep -q 'INITCK unsupported boundary: STRING/LSTRING INSERT operand' "$work/error" || die 'INSERT INITCK function diagnostic'
  fi
  pass "INSERT explicit INITCK string boundary: $source"
done
printf '%s\n' 'PROGRAM boundary; VAR t: LSTRING(4);' \
  "BEGIN t := 'ab'; {\$INITCK+} INSERT('x', t, 1) END." > "$work/initck.pas"
if bin/pascal1981 -O0 -S "$work/initck.pas" -o "$work/initck.ll" 2> "$work/error"; then die 'INSERT INITCK accepted destination'; fi
grep -q 'INITCK unsupported boundary: global or captured storage' "$work/error" || die 'INSERT INITCK destination diagnostic'
pass 'INSERT explicit INITCK boundary: destination read'
# CPU DEVICE enforces the host contract; NVPTX retains the unchecked boundary.
printf '%s\n' 'DEVICE INTERFACE;' 'UNIT INSU (check);' 'PROCEDURE check;' 'END;' > "$work/ins.inc"
printf '%s\n' '(*$INCLUDE:'\''ins.inc'\''*)' 'DEVICE IMPLEMENTATION OF INSU;' \
  'PROCEDURE check;' 'VAR t: LSTRING(3);' "BEGIN t := 'abc'; INSERT('x', t, 1) END;" '.' > "$work/ins.impl"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended -O0 -S ins.impl -o cpu.ll)
grep -q 'call void @pas_insert_error' "$work/cpu.ll" || die 'CPU DEVICE INSERT guard'
pass 'CPU DEVICE INSERT guard'
printf '%s\n' '(*$INCLUDE:'\''ins.inc'\''*)' 'PROGRAM cpu;' 'USES INSU (check);' \
  "BEGIN LAUNCH(check, 1, 1); WRITELN('wrong') END." > "$work/cpu.pas"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended cpu.pas ins.impl -o cpu)
rc=0
{ "$work/cpu" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
[[ $rc == 134 && ! -s $work/output ]] || die "CPU DEVICE INSERT exit/output $rc"
grep -qxF 'runtime error: INSERT length 4 exceeds capacity 3 at line 5 column 19' "$work/error"
pass 'CPU DEVICE INSERT runtime failure'
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended --device-triple nvptx64-nvidia-cuda -S ins.impl -o gpu.ll)
if grep -q 'pas_insert_error\|pas_insert_position_error' "$work/gpu.ll"; then die 'NVPTX emitted host INSERT failure'; fi
pass 'NVPTX existing unchecked INSERT boundary'
finish 'INSERT'
