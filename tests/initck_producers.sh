#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# INITCK scalar producers beyond literal assignment: unchecked copies carry
# their source state, READ/READLN destinations and FOR control variables are
# producers. Never run unchecked bad reads as if their output meant anything.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ulimit -c 0

# expect_ok NAME EXPECTED-STDOUT [STDIN]: both dialects, O0/O2, INITCK as written.
expect_ok() {
  local name=$1 expected=$2 input=${3:-}
  printf '%b' "$expected" > "$work/$name.expected"
  for dialect in vintage extended; do
    for opt in 0 2; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/$name.pas" -o "$work/$name" 2> "$work/err"
      test ! -s "$work/err"
      printf '%b' "$input" | "$work/$name" > "$work/actual" 2> "$work/err"
      diff -u "$work/$name.expected" "$work/actual"
      test ! -s "$work/err"
    done
  done
}

# expect_fail NAME STDOUT-PREFIX ERROR-LINE [STDIN]: exactly one INITCK error.
expect_fail() {
  local name=$1 prefix=$2 error=$3 input=${4:-}
  printf '%b' "$prefix" > "$work/$name.expected"
  printf '%s\n' "$error" > "$work/$name.expected-err"
  for opt in 0 2; do
    bin/pascal1981 -O"$opt" "$work/$name.pas" -o "$work/$name" 2> "$work/err"
    test ! -s "$work/err"
    status=0
    { printf '%b' "$input" | "$work/$name" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
    test "$status" -ne 0
    diff -u "$work/$name.expected" "$work/actual"
    diff -u "$work/$name.expected-err" "$work/err"
  done
}

# --- Assignment: an unchecked copy propagates, never manufactures, state. ---
cat > "$work/copy-ok.pas" <<'PAS'
PROGRAM copyok;
PROCEDURE probe;
VAR x, y, z: INTEGER; b: BOOLEAN; c, d: CHAR;
BEGIN
  {$INITCK-}
  x := 0; y := x; z := y - 32767 - 1;
  b := y = z;
  c := 'q'; d := c;
  {$INITCK+} WRITELN(y, ' ', z, ' ', ORD(b), d)
  {$INITCK-}
END;
PROCEDURE retaint;
VAR unset, y: INTEGER;
BEGIN
  { Overwriting a slot that received unset state initializes it again. }
  {$INITCK-} y := unset; y := 7;
  {$INITCK+} WRITELN(y)
  {$INITCK-}
END;
BEGIN probe; retaint END.
PAS
expect_ok copy-ok '0 -32768 0q\n7\n'

for kind in plain expr chain bool char not; do
  case "$kind" in
    plain) decl='x, y: INTEGER'; body='y := x' ;;
    expr) decl='x, y: INTEGER'; body='y := (x * 0) + 1' ;;
    chain) decl='x, t, y: INTEGER'; body='t := x; y := t' ;;
    bool) decl='x: INTEGER; y: BOOLEAN'; body='y := x = x' ;;
    char) decl='x, y: CHAR'; body='y := x' ;;
    not) decl='x, y: BOOLEAN'; body='y := NOT x' ;;
  esac
  cat > "$work/copy-bad.pas" <<PAS
PROGRAM copybad;
PROCEDURE probe;
VAR $decl;
BEGIN
  {\$INITCK-} $body;
  {\$INITCK+} WRITELN('prefix');
  WRITELN(y)
  {\$INITCK-}
END;
BEGIN probe END.
PAS
  expect_fail copy-bad 'prefix\n' 'runtime error: INITCK uninitialized local y at line 7 column 11'
done

# O0 shape: a literal store publishes constant TRUE with no accumulator; an
# unchecked tracked source ANDs its state into one after the data load.
cat > "$work/copy-ir.pas" <<'PAS'
PROGRAM copyir;
PROCEDURE probe;
VAR x, y: INTEGER;
BEGIN {$INITCK-} x := 1; y := x END;
BEGIN probe END.
PAS
bin/pascal1981 -O0 -S "$work/copy-ir.pas" -o "$work/copy-ir.ll"
python3 - "$work/copy-ir.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
# x, y and one accumulator (not the predeclared files' buffer states)
assert len(re.findall(r'%(?!file_initck)[\w.]+ = alloca i1,', ir)) == 3, ir
assert 'store i1 true, ptr %initck.x' in ir
assert 'pas_initck_error' not in ir
src = ir.index('load i1, ptr %initck.x')
data = ir.index('store i16 %', src)
publish = re.search(r'store i1 %initck\.value\d*, ptr %initck\.y', ir)
assert publish and src < data < publish.start()
PY

# --- READ/READLN: successful conversion initializes direct destinations. ---
cat > "$work/read-ok.pas" <<'PAS'
PROGRAM readok;
PROCEDURE probe;
VAR n: INTEGER; c: CHAR; b: BOOLEAN;
BEGIN
  {$INITCK+}
  READ(n); READ(c); READLN(b);
  WRITELN(n + 1, c, ORD(b));
  READLN(n, c);
  WRITELN(n, c)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok read-ok '-32767x1\n0y\n' '-32768xTRUE\n0y\n'
# A READ of one destination does not initialize another.
cat > "$work/read-bad.pas" <<'PAS'
PROGRAM readbad;
PROCEDURE probe;
VAR n, m: INTEGER;
BEGIN
  {$INITCK+}
  READLN(n); WRITELN(n);
  WRITELN(m)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_fail read-bad '5\n' 'runtime error: INITCK uninitialized local m at line 7 column 11' '5\n'
# Status gating: success sets state; a trapped file failure keeps the prior
# state. TRAP is not reachable from Pascal source today, so assert the IR.
cat > "$work/read-ir.pas" <<'PAS'
PROGRAM readir;
PROCEDURE probe(VAR f: TEXT);
VAR n: INTEGER;
BEGIN READ(f, n) END;
BEGIN END.
PAS
bin/pascal1981 -O0 -S "$work/read-ir.pas" -o "$work/read-ir.ll"
python3 - "$work/read-ir.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
call = re.search(r'(%\d+) = call i32 @pas_fread_int16\(', ir)
assert call, ir
rest = ir[call.end():]
ok = re.search(r'(%\d+) = icmp eq i32 ' + re.escape(call.group(1)) + r', 0', rest)
assert ok
sel = re.search(r'%initck\.read\d* = select i1 ' + re.escape(ok.group(1)) + r', i1 true, i1 (%\d+)', rest)
assert sel
assert re.search(r'store i1 %initck\.read\d*, ptr %initck\.n', rest)
PY

# --- FOR control: producer per iteration; undefined after natural exit. ---
cat > "$work/for-ok.pas" <<'PAS'
PROGRAM forok;
PROCEDURE probe;
LABEL 9;
VAR i, s: INTEGER; c: CHAR; b: BOOLEAN;
BEGIN
  {$INITCK+}
  s := 0;
  FOR i := 1 TO 3 DO s := s + i;
  FOR i := 3 DOWNTO 1 DO s := s + i;
  WRITELN(s);
  FOR i := 1 TO 10 DO IF i = 4 THEN BREAK;
  WRITELN(i);
  FOR i := 1 TO 10 DO IF i = 6 THEN GOTO 9;
  9: WRITELN(i);
  FOR c := 'x' TO 'z' DO WRITE(c);
  FOR b := FALSE TO TRUE DO WRITE(ORD(b));
  WRITELN;
  FOR i := 1 TO 0 DO WRITELN('never');
  i := -32768; WRITELN(i)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok for-ok '12\n4\n6\nxyz01\n-32768\n'
for kind in after zero char downto taintstart cycle; do
  decl='i: INTEGER'; var='i'
  case "$kind" in
    after) loop='FOR i := 1 TO 2 DO WRITELN(i)'; prefix='1\n2\n' ;;
    zero) loop='FOR i := 1 TO 0 DO WRITELN(i)'; prefix='' ;;
    char) decl='i: CHAR'; loop="FOR i := 'a' TO 'b' DO WRITELN(i)"; prefix='a\nb\n' ;;
    downto) loop='FOR i := 2 DOWNTO 1 DO WRITELN(i)'; prefix='2\n1\n' ;;
    cycle) loop='FOR i := 1 TO 2 DO BEGIN IF i = 2 THEN CYCLE; WRITELN(i) END'; prefix='1\n' ;;
    taintstart) decl='i, u: INTEGER'
      loop='{$INITCK-} FOR i := u TO u DO {$INITCK+} WRITELN(i) {$INITCK-}'; prefix='' ;;
  esac
  cat > "$work/for-bad.pas" <<PAS
PROGRAM forbad;
PROCEDURE probe;
VAR $decl;
BEGIN
  {\$INITCK+}
  $loop;
  WRITELN($var)
  {\$INITCK-}
END;
BEGIN probe END.
PAS
  if [ "$kind" = taintstart ]; then
    # The start value's unset state flows into the first iteration's read.
    col=$(( $(printf '%s' "$loop" | grep -bo 'WRITELN(i)' | cut -d: -f1) + 11 ))
    expect_fail for-bad '' "runtime error: INITCK uninitialized local i at line 6 column $col"
  else
    expect_fail for-bad "$prefix" 'runtime error: INITCK uninitialized local i at line 7 column 11'
  fi
done
# FOR over excluded control storage is not itself a consumer: the statement's
# own comparisons read a value it just wrote. Compile only.
cat > "$work/for-global.pas" <<'PAS'
PROGRAM forglobal;
VAR g: INTEGER;
PROCEDURE probe;
VAR e: INTEGER32;
BEGIN {$INITCK+} FOR g := 1 TO 2 DO ; FOR e := 1 TO 2 DO ; {$INITCK-} END;
BEGIN probe END.
PAS
bin/pascal1981 --dialect extended -O0 -S "$work/for-global.pas" -o "$work/for-global.ll" 2> "$work/err"
test ! -s "$work/err"

# --- Producers through formals (routine-boundary bindings). ---
# READ into a VAR formal initializes the caller's local; READ into a value
# formal overwrites an unset transported state. FOR over a value formal is
# an ordinary producer; FOR over a VAR formal leaves the CALLER's storage
# undefined after natural termination, so the caller's checked read fails.
cat > "$work/formal-ok.pas" <<'PAS'
PROGRAM formalok;
{$INITCK+}
PROCEDURE getv(VAR n: INTEGER; VAR c: CHAR); BEGIN READ(n); READLN(c) END;
PROCEDURE getval(n: INTEGER); BEGIN READLN(n); WRITELN(n) END;
PROCEDURE count(n: INTEGER); BEGIN FOR n := n TO n + 1 DO WRITE(n); WRITELN END;
PROCEDURE probe;
VAR x, u: INTEGER; c: CHAR;
BEGIN
  getv(x, c); WRITELN(x, c);
  {$INITCK-} getval(u); {$INITCK+}
  count(-32768)
END;
BEGIN probe END.
{$INITCK-}
PAS
expect_ok formal-ok '7z\n9\n-32768-32767\n' '7z\n9\n'
cat > "$work/formal-bad.pas" <<'PAS'
PROGRAM formalbad;
PROCEDURE loop(VAR v: INTEGER); BEGIN FOR v := 1 TO 2 DO WRITELN(v) END;
PROCEDURE probe;
VAR x: INTEGER;
BEGIN
  x := 5; loop(x);
  {$INITCK+} WRITELN(x)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_fail formal-bad '1\n2\n' 'runtime error: INITCK uninitialized local x at line 7 column 22'
echo 'PASS: INITCK scalar producers: unchecked copies, READ/READLN, FOR control, through formals'
