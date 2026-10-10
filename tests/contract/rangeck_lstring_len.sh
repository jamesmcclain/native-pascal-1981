#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# LSTRING length-byte stores (assignment, READ, VAR CHAR actuals) check capacity.
require bin/pascal1981 bin/parser bin/codegen runtime/build/libpascalrt.a
cc=${CC:-clang}
# len_err LENGTH CAP [LINE COLUMN]: the run's stderr is exactly the LSTRING
# length diagnostic (any location unless one is given).
len_err() {
  grep -qxE "runtime error: RANGECK LSTRING length $1 exceeds capacity $2 at line ${3:-[0-9]+} column ${4:-[0-9]+}" "$work/error"
}
for dialect in vintage extended; do
  for flag in + -; do
    opposite=+; [[ $flag != + ]] || opposite=-
    cat > "$work/good.pas" <<GOOD
PROGRAM good;
TYPE Short = LSTRING(3); Box = RECORD item: Short END;
VAR t: Short; a: ARRAY[1..2] OF Short; p: ^Short;
    r: Box; z: LSTRING(0); big: LSTRING(256); calls, zero: INTEGER;
FUNCTION idx: INTEGER;
BEGIN calls := calls + 1; idx := 1 END;
FUNCTION length: CHAR;
BEGIN calls := calls + 1; length := CHR(3) END;
PROCEDURE change(VAR v: Short);
BEGIN v.LEN := CHR(2) END;
BEGIN
  t := 'abc'; a[1] := 'abc'; a[2] := 'abc'; r.item := 'abc';
  z := ''; big := ''; calls := 0; zero := 0;
  {\$RANGECK$flag}
  t.LEN := {\$RANGECK$opposite} CHR(0);
  {\$RANGECK$flag}
  a[idx].LEN := length;
  p := ADR t; p^.LEN := CHR(1);
  IF ORD(p^.LEN) <> 1 THEN WRITELN('wrong pointer length');
  WITH r DO item.LEN := CHR(2);
  z.LEN := CHR(0); big.LEN := CHR(255);
  z[zero] := CHR(0); t[zero] := CHR(3);
  t[idx] := CHR(200);
  IF ORD(t[1]) <> 200 THEN WRITELN('wrong payload');
  change(t);
  WRITELN(ORD(t.LEN), ' ', a[1], ' ', a[2], ' ', r.item);
  WRITELN(ORD(z.LEN), ' ', ORD(big.LEN), ' ', calls)
END.
GOOD
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/good.pas" -o "$work/good"
      "$work/good" > "$work/output" 2> "$work/error"
      printf '2 abc abc ab\n0 255 3\n' > "$work/expected.out"
      diff -u "$work/expected.out" "$work/output"
      [[ ! -s $work/error ]] || die "$dialect valid LEN$flag O$opt stderr"
      pass "$dialect valid LEN$flag O$opt: zero, exact, byte limit, indexed/dereferenced/WITH/VAR targets, once-only calls"
    done
  done
  for spec in '0 1' '3 4' '3 200'; do
    read -r cap length <<< "$spec"
    for flag in + -; do
      opposite=+; [[ $flag != + ]] || opposite=-
      cat > "$work/bad.pas" <<BAD
PROGRAM bad;
VAR t: LSTRING($cap);
BEGIN
  t := '';
  WRITELN('before');
  {\$RANGECK$flag}
  t.LEN := {\$RANGECK$opposite} CHR($length);
  WRITELN('wrong')
END.
BAD
      bin/pascal1981 --dialect "$dialect" -O0 -S "$work/bad.pas" -o "$work/bad.ll"
      expected=0; [[ $flag != + ]] || expected=1
      [[ $(grep -c 'call void @pas_lstring_length_error' "$work/bad.ll" || true) == "$expected" ]] || die "$dialect capacity $cap LEN$flag IR guards"
      if [[ $flag == - ]]; then
        pass "$dialect capacity $cap disabled guard-free IR (not executed)"
        continue
      fi
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
        rc=0
        { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        [[ $rc == 134 ]] || die "$dialect capacity $cap LEN O$opt exit $rc"
        printf 'before\n' > "$work/expected.out"
        printf 'runtime error: RANGECK LSTRING length %s exceeds capacity %s at line 7 column 3\n' "$length" "$cap" > "$work/expected.err"
        diff -u "$work/expected.out" "$work/output"
        diff -u "$work/expected.err" "$work/error"
        pass "$dialect capacity $cap checked LEN $length O$opt"
      done
    done
  done
done
# The same guard applies to indirect targets; the RHS reads a different
# LSTRING length byte and must not overwrite the target's saved capacity.
for dialect in vintage extended; do
  for math in + -; do
    for target in 'a[idx].LEN' 'p^.LEN' 'r.item.LEN' 'WITH r DO item.LEN' 'change(t)' 't[0]' 't[zero]' 'p^[zero]' 'a[idx][zero]' 't[CHR(0)]' 't[FALSE]' 't[red]' 't[w]'; do
      assignment="$target := sourcebyte"; [[ $target != 'change(t)' ]] || assignment=$target
      cat > "$work/indirect.pas" <<INDIRECT
{\$MATHCK$math}{\$RANGECK+}
PROGRAM indirect;
TYPE Short = LSTRING(3); Box = RECORD item: Short END; Color = (red, green);
VAR t: Short; a: ARRAY[1..2] OF Short; p: ^Short;
    r: Box; big: LSTRING(255); zero: INTEGER; w: WORD;
FUNCTION idx: INTEGER;
BEGIN idx := 1 END;
FUNCTION sourcebyte: CHAR;
BEGIN WRITELN('source'); sourcebyte := big.LEN END;
PROCEDURE change(VAR v: Short);
BEGIN v.LEN := sourcebyte END;
BEGIN
  t := 'abc'; a[1] := 'abc'; r.item := 'abc'; p := ADR t; zero := 0; w := 0;
  big := ''; big.LEN := CHR(200);
  WRITELN('before');
  $assignment;
  WRITELN('wrong')
END.
INDIRECT
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/indirect.pas" -o "$work/indirect"
        rc=0
        { "$work/indirect" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        [[ $rc == 134 ]] || die "$dialect indirect LEN $target MATHCK$math O$opt exit $rc"
        printf 'before\nsource\n' > "$work/expected.out"
        diff -u "$work/expected.out" "$work/output"
        len_err 200 3
        pass "$dialect indirect LEN $target MATHCK$math O$opt"
      done
    done
  done
done
# Writers other than assignment: READ into the length byte and a VAR CHAR
# formal bound to it are checked as soon as the byte is stored (READ) or
# the call returns (VAR). Payload bytes stay unrestricted.
for dialect in vintage extended; do
  for spec in 'READ(t.LEN)|8|120' 'READ(t[0])|8|120' 'READ(t[zero])|8|120' \
              'READ(f, t.LEN)|11|120' 'setc(t.LEN)|8|200' 'setc(t[zero])|8|200' \
              'setc(p^.LEN)|8|200'; do
    IFS='|' read -r writer column length <<< "$spec"
    cat > "$work/writer.pas" <<WRITER
{\$RANGECK+}
PROGRAM writer(INPUT, OUTPUT);
VAR t: LSTRING(3); p: ^LSTRING(3); zero: INTEGER; f: TEXT;
PROCEDURE setc(VAR c: CHAR);
BEGIN c := CHR(200) END;
BEGIN
  t := 'abc'; p := ADR t; zero := 0;
  ASSIGN(f, 'in.txt'); RESET(f);
  WRITELN('before');
  $writer;
  WRITELN('wrong ', ORD(t.LEN))
END.
WRITER
    for opt in 0 2; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/writer.pas" -o "$work/writer"
      printf 'x\n' > "$work/in.txt"
      rc=0
      { (cd "$work" && exec ./writer < in.txt > output 2> error); } 2>/dev/null || rc=$?
      [[ $rc == 134 ]] || die "$dialect $writer O$opt exit $rc"
      printf 'before\n' > "$work/expected.out"
      diff -u "$work/expected.out" "$work/output"
      len_err "$length" 3 10 "$column" || die "$dialect $writer O$opt diagnostic: $(cat "$work/error")"
      pass "$dialect checked LEN writer $writer O$opt"
    done
  done
  cat > "$work/writers_ok.pas" <<'WRITERS'
{$RANGECK+}
PROGRAM writers_ok(INPUT, OUTPUT);
VAR t: LSTRING(3); zero: INTEGER; c: CHAR;
PROCEDURE setc(VAR c: CHAR; v: INTEGER);
BEGIN c := CHR(v) END;
BEGIN
  t := 'abc'; zero := 0;
  setc(t[1], 200);
  setc(t.LEN, 2);
  setc(t[zero], 3);
  READ(c);
  READ(t[2]);
  WRITELN(ORD(t.LEN), ' ', ORD(t[1]), ' ', t[2]);
  {$RANGECK-}
  setc(t.LEN, 200);
  WRITELN(ORD(t.LEN))
END.
WRITERS
  bin/pascal1981 --dialect "$dialect" -O1 "$work/writers_ok.pas" -o "$work/writers_ok"
  printf 'xy\n' | "$work/writers_ok" > "$work/output" 2> "$work/error"
  printf '3 200 y\n200\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  [[ ! -s $work/error ]] || die "$dialect LEN writers stderr"
  pass "$dialect unchecked payload writers, in-capacity LEN writers, RANGECK- call site"
done
# Observe all bytes of the selected and neighboring slots before abort.
# This also pins selection/RHS once-only evaluation and source side effects.
bin/pascal1981 --dialect extended -O0 -S tests/contract/fixtures/lstring_len_publication.pas -o "$work/publication.ll"
python3 - "$work/publication.ll" <<'PY'
import re
import sys
from pathlib import Path

ir = Path(sys.argv[1]).read_text()
main = ir[ir.index('define i32 @main('):].split('\n}', 1)[0]
assert main.count('call i16 @idx(') == 1
assert main.count('call i8 @source(') == 1
assert main.index('call i16 @idx(') < main.index('call i8 @source(')
assert 'call void @pas_lstring_length_error' in main[main.index('call i8 @source('):]
blocks = re.split(r'(?m)^([\w.]+):[^\n]*\n', main)
checked = 0
for label, block in zip(blocks[1::2], blocks[2::2]):
    if label.startswith('length.bad'):
        assert 'call void @pas_lstring_length_error' in block
        assert 'unreachable' in block and not re.search(r'\bstore\b', block)
        checked += 1
    if label.startswith('length.ok'):
        assert re.search(r'\bstore i8 ', block)
assert checked == 2  # big.LEN's legal setup and a[idx].LEN's checked store
PY
pass 'LEN O0 target/source/check/store order and write-free failure blocks'
for opt in 0 1 2 3; do
  "$cc" -O"$opt" "$work/publication.ll" tests/contract/fixtures/lstring_len_publication.c \
    runtime/build/libpascalrt.a -Wl,--wrap=abort -o "$work/publication"
  rc=0
  "$work/publication" > "$work/output" 2> "$work/error" || rc=$?
  [[ $rc == 134 ]] || die "LEN publication O$opt exit $rc"
  printf 'PASS: LEN destination unchanged; target and source evaluated once\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  len_err 200 3
  pass "LEN failed publication and once-only target/source O$opt"
done
# Repeat observation with a dynamically selected index-zero alias.
python3 - "$work/indexed.pas" <<'PY'
import sys
from pathlib import Path

source = Path('tests/contract/fixtures/lstring_len_publication.pas').read_text()
source = source.replace('FUNCTION source: CHAR;',
    'FUNCTION zeroidx: INTEGER;\nBEGIN TargetTick; zeroidx := 0 END;\nFUNCTION source: CHAR;')
Path(sys.argv[1]).write_text(source.replace('a[idx].LEN := source', 'a[idx][zeroidx] := source'))
PY
bin/pascal1981 --dialect extended -O0 -S "$work/indexed.pas" -o "$work/indexed.ll"
for opt in 0 1 2 3; do
  "$cc" -O"$opt" -DEXPECTED_TARGET_TICKS=2 "$work/indexed.ll" tests/contract/fixtures/lstring_len_publication.c \
    runtime/build/libpascalrt.a -Wl,--wrap=abort -o "$work/indexed"
  rc=0
  "$work/indexed" > "$work/output" 2> "$work/error" || rc=$?
  [[ $rc == 134 ]] || die "index-zero LEN publication O$opt exit $rc"
  diff -u "$work/expected.out" "$work/output"
  len_err 200 3
  pass "index-zero LEN failed publication and once-only indexes/source O$opt"
done
# First-token assignment snapshots own the guard, not RHS directives.
cat > "$work/snapshots.pas" <<'SNAPSHOTS'
PROGRAM snapshots; VAR t: LSTRING(3);
BEGIN t := 'abc';
  {$RANGECK+}
  IF TRUE THEN BEGIN {$RANGECK-} t.LEN := CHR(4) END;
  {$RANGECK+}
  t.LEN := {$RANGECK-} CHR(4);
  t.LEN := {$RANGECK+} CHR(4)
END.
SNAPSHOTS
bin/pascal1981 -O0 -S "$work/snapshots.pas" -o "$work/snapshots.ll"
[[ $(grep -c 'call void @pas_lstring_length_error' "$work/snapshots.ll") == 1 ]] || die 'LEN nested/sibling snapshots'
pass 'LEN nested/sibling assignment snapshots (invalid unchecked stores not executed)'
printf '%s\n' 'PROGRAM unchecked; VAR t: LSTRING(3); zero: INTEGER;' \
  "BEGIN zero := 0; {\$RANGECK-} t[zero] := {\$RANGECK+} CHR(200) END." > "$work/unchecked.pas"
bin/pascal1981 -O0 -S "$work/unchecked.pas" -o "$work/unchecked.ll"
if grep -q 'pas_lstring_length_error' "$work/unchecked.ll"; then die 'disabled index-zero LEN guard'; fi
pass 'index-zero RANGECK- guard-free IR (not executed)'
# Legacy assignments inherit the enclosing/root RANGECK policy.
cat > "$work/legacy.pas" <<'LEGACY'
PROGRAM legacy; VAR t: LSTRING(3);
BEGIN t := ''; t.LEN := CHR(200) END.
LEGACY
bin/lexer < "$work/legacy.pas" | bin/parser | bin/typechecker > "$work/typed.json"
python3 - "$work/typed.json" "$work/legacy.json" <<'PY'
import json
import sys
from pathlib import Path

def strip(node):
    if isinstance(node, dict):
        return {k: strip(v) for k, v in node.items() if k != 'rangeck'}
    if isinstance(node, list):
        return [strip(v) for v in node]
    return node

Path(sys.argv[2]).write_text(json.dumps(strip(json.loads(Path(sys.argv[1]).read_text()))))
PY
bin/codegen < "$work/legacy.json" > "$work/legacy.ll"
grep -q 'call void @pas_lstring_length_error' "$work/legacy.ll" || die 'legacy LEN enabled inheritance'
pass 'legacy LEN enabled inheritance'
# CPU DEVICE checks; NVPTX retains the explicit host-runtime exclusion.
printf '%s\n' 'DEVICE INTERFACE;' 'UNIT LENU (check);' 'PROCEDURE check;' 'END;' > "$work/len.inc"
printf '%s\n' "(*\$INCLUDE:'len.inc'*)" 'DEVICE IMPLEMENTATION OF LENU;' \
  'PROCEDURE check;' 'VAR t: LSTRING(3);' "BEGIN t := ''; t.LEN := CHR(200) END;" '.' > "$work/len.impl"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended -O0 -S len.impl -o cpu.ll)
grep -q 'call void @pas_lstring_length_error' "$work/cpu.ll" || die 'CPU DEVICE LEN guard missing'
pass 'CPU DEVICE LEN guard'
printf '%s\n' "(*\$INCLUDE:'len.inc'*)" 'PROGRAM cpu;' 'USES LENU (check);' \
  "BEGIN LAUNCH(check, 1, 1); WRITELN('wrong') END." > "$work/cpu.pas"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended cpu.pas len.impl -o cpu)
rc=0
{ "$work/cpu" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
[[ $rc == 134 && ! -s $work/output ]] || die "CPU DEVICE LEN exit/output $rc"
len_err 200 3
pass 'CPU DEVICE LEN runtime failure'
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended --device-triple nvptx64-nvidia-cuda -S len.impl -o gpu.ll)
if grep -q 'pas_lstring_length_error' "$work/gpu.ll"; then die 'NVPTX emitted host LEN failure'; fi
pass 'NVPTX existing unchecked LEN boundary'
finish 'RANGECK LSTRING LEN'
