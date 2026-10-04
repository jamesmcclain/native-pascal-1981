#!/usr/bin/env bash
# INITCK routine boundaries: supplied parameter values, the agreed zero/default
# result bytes, and calling conventions must survive instrumentation. Never
# run unchecked bad reads as if their output meant anything.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ulimit -c 0

# A correctly initialized program, apart from functions that deliberately
# never assign their result: those return the retained native zero/default
# bytes (scalar, REAL, pointer, coerced and sret records) when INITCK is off
# at the return. Value, VAR and CONST formals carry 0, FALSE, CHR(0) and the
# full-range INTEGER minimum unchanged; recursion and nesting are included.
cat > "$work/plain.pas" <<'PAS'
PROGRAM routines;
TYPE
  Pair = RECORD a, b: INTEGER END;
  Big = RECORD a, b, c, d, e, f, g, h, i, j: INTEGER END;
  PInt = ^INTEGER;
FUNCTION echo(i: INTEGER; b: BOOLEAN; c: CHAR): INTEGER;
VAR t: INTEGER; u: BOOLEAN;
BEGIN
  t := i; u := b;
  {@ON} IF u THEN echo := t ELSE {@OFF} echo := ORD(c)
END;
PROCEDURE swap(VAR x, y: INTEGER);
VAR t: INTEGER;
BEGIN t := x; x := y; {@ON} y := t {@OFF} END;
PROCEDURE view(CONST c: CHAR; CONST p: Pair);
BEGIN WRITELN(ORD(c), ' ', p.a, ' ', p.b) END;
FUNCTION noint: INTEGER; BEGIN END;
FUNCTION nobool: BOOLEAN; BEGIN END;
FUNCTION nochar: CHAR; BEGIN END;
FUNCTION noreal: REAL; BEGIN END;
FUNCTION noptr: PInt; BEGIN END;
FUNCTION nopair: Pair; BEGIN END;
FUNCTION nobig: Big; BEGIN END;
FUNCTION early(n: INTEGER): INTEGER;
BEGIN IF n > 0 THEN BEGIN early := n; {@ON} RETURN END {@OFF} END;
FUNCTION fact(n: INTEGER): INTEGER;
BEGIN IF n <= 1 THEN fact := 1 ELSE fact := n * fact(n - 1) END;
PROCEDURE outer(n: INTEGER);
VAR m: INTEGER;
  FUNCTION inner(k: INTEGER): INTEGER;
  BEGIN inner := k + 1 END;
BEGIN m := inner(n); WRITELN(m) END;
VAR x, y: INTEGER; p: Pair; bg: Big; ch: CHAR;
BEGIN
  {@OFF}
  WRITELN(echo(-32768, TRUE, 'a'), ' ', echo(0, FALSE, CHR(0)));
  x := 1; y := -32768; swap(x, y); WRITELN(x, ' ', y);
  p.a := 3; p.b := 4; ch := 'z'; view(ch, p);
  WRITELN(noint, ' ', ORD(nobool), ' ', ORD(nochar), ' ', noreal:3:1, ' ', noptr = NIL);
  p := nopair; bg := nobig; WRITELN(p.a, ' ', p.b, ' ', bg.a, ' ', bg.j);
  WRITELN(early(0), ' ', early(5), ' ', fact(5));
  outer(41)
END.
PAS
printf -- '-32768 0\n-32768 1\n122 3 4\n0 0 0 0.0 TRUE\n0 0 0 0\n0 5 120\n42\n' > "$work/expected"
# plain: no directives. checked: INITCK+ wherever the current slice accepts an
# enabled read (tracked locals) and at a RETURN after the result is assigned.
# Unassigned results keep INITCK off at their return: the default bytes are
# the agreed INITCK-off behavior, not an initialization.
python3 - "$work" <<'PY'
import sys
work = sys.argv[1]
src = open(f'{work}/plain.pas').read()
open(f'{work}/plain.pas', 'w').write(src.replace('{@ON}', '').replace('{@OFF}', ''))
open(f'{work}/checked.pas', 'w').write(
    src.replace('{@ON}', '{$INITCK+}').replace('{@OFF}', '{$INITCK-}'))
PY
for mode in plain checked; do
  for dialect in vintage extended; do
    for opt in 0 2; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/$mode.pas" -o "$work/$mode" 2> "$work/err"
      test ! -s "$work/err"
      "$work/$mode" > "$work/actual" 2> "$work/err"
      diff -u "$work/expected" "$work/actual"
      test ! -s "$work/err"
    done
  done
done
# Calling conventions: INITCK adds no hidden parameters or result changes.
# Every definition and Pascal call site is pinned, and checking-enabled
# regions emit exactly the same signatures as the unannotated program.
for mode in plain checked; do
  bin/pascal1981 -O0 -S "$work/$mode.pas" -o "$work/$mode.ll"
  python3 - "$work/$mode.ll" > "$work/$mode.sig" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
names = 'echo|swap|view|noint|nobool|nochar|noreal|noptr|nopair|nobig|early|fact|outer|inner'
for line in ir.splitlines():
    for kind in ('define', 'call'):
        m = re.search(kind + r' (.*?) @(' + names + r')\((.*)\)', line)
        if m:
            args = re.sub(r'%\d+', '%', m.group(3))
            print(f'{kind} {m.group(1)} {m.group(2)}({args})')
PY
done
cat > "$work/expected.sig" <<'SIG'
call i16 echo(i16 -32768, i1 true, i8 97)
call i16 echo(i16 0, i1 false, i8 0)
call void swap(ptr @x, ptr @y)
call void view(ptr @ch, ptr @p)
call i16 noint()
call i1 nobool()
call i8 nochar()
call double noreal()
call ptr noptr()
call i32 nopair()
call void nobig(ptr noalias sret({ i16, i16, i16, i16, i16, i16, i16, i16, i16, i16 }) align 8 %)
call i16 early(i16 0)
call i16 early(i16 5)
call i16 fact(i16 5)
call void outer(i16 41)
define i16 echo(i16 %, i1 %, i8 %)
define void swap(ptr %, ptr %)
define void view(ptr %, ptr %)
define i16 noint()
define i1 nobool()
define i8 nochar()
define double noreal()
define ptr noptr()
define i32 nopair()
define void nobig(ptr noalias sret({ i16, i16, i16, i16, i16, i16, i16, i16, i16, i16 }) align 8 %)
define i16 early(i16 %)
define i16 fact(i16 %)
call i16 fact(i16 %)
define void outer(i16 %)
call i16 inner(i16 %)
define i16 inner(i16 %)
SIG
diff -u "$work/expected.sig" "$work/plain.sig"
diff -u "$work/expected.sig" "$work/checked.sig"

# --- Value formals and tracked scalar results (INTEGER/BOOLEAN/CHAR). ---
# expect_ok/expect_fail: as in initck_producers.sh.
expect_ok() {
  local name=$1 expected=$2
  printf '%b' "$expected" > "$work/$name.expected"
  for dialect in vintage extended; do
    for opt in 0 2; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/$name.pas" -o "$work/$name" 2> "$work/err"
      test ! -s "$work/err"
      "$work/$name" > "$work/actual" 2> "$work/err"
      diff -u "$work/$name.expected" "$work/actual"
      test ! -s "$work/err"
    done
  done
}
expect_fail() {
  local name=$1 prefix=$2 error=$3
  printf '%b' "$prefix" > "$work/$name.expected"
  printf '%s\n' "$error" > "$work/$name.expected-err"
  for opt in 0 2; do
    bin/pascal1981 -O"$opt" "$work/$name.pas" -o "$work/$name" 2> "$work/err"
    test ! -s "$work/err"
    status=0
    { "$work/$name" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
    test "$status" -ne 0
    diff -u "$work/$name.expected" "$work/actual"
    diff -u "$work/$name.expected-err" "$work/err"
  done
}
# Checked everywhere except where noted. A formal is initialized on entry
# with its actual's state; a result starts unset per activation and becomes
# initialized only by assignment to the function name; an unset actual that
# the callee ignores or overwrites is never a failure (only reads are).
cat > "$work/transport-ok.pas" <<'PAS'
PROGRAM transport;
{$INITCK+}
FUNCTION pick(i: INTEGER; b: BOOLEAN; c: CHAR): INTEGER;
BEGIN IF b THEN pick := i ELSE pick := ORD(c) END;
FUNCTION same(b: BOOLEAN): BOOLEAN; BEGIN same := b END;
FUNCTION letter(c: CHAR): CHAR; BEGIN letter := c END;
PROCEDURE ignore(n: INTEGER); BEGIN END;
PROCEDURE overwrite(n: INTEGER); BEGIN n := 4; WRITELN(n) END;
FUNCTION fact(n: INTEGER): INTEGER;
BEGIN IF n <= 1 THEN BEGIN fact := 1; RETURN END; fact := n * fact(n - 1) END;
FUNCTION twice(n: INTEGER): INTEGER; BEGIN twice := n + n END;
PROCEDURE probe;
VAR x, u: INTEGER; b: BOOLEAN; c: CHAR;
BEGIN
  x := pick(-32768, TRUE, 'a'); WRITELN(x, ' ', pick(0, FALSE, CHR(0)));
  b := same(FALSE); c := letter('q'); WRITELN(ORD(b), c);
  {$INITCK-} ignore(u); overwrite(u); {$INITCK+}
  x := twice(twice(fact(4))); WRITELN(x, ' ', fact(7))
END;
BEGIN probe END.
{$INITCK-}
PAS
expect_ok transport-ok '-32768 0\n0q\n4\n96 5040\n'

# Negative cases: kind, failing line, column, stdout prefix. Each fixture
# prints 'prefix' first and never reaches 'after'.
for kind in actual formal formalcopy endresult returnresult taintresult partial recursion nested; do
  routines=''; locals='u, x: INTEGER'; body=''; prefix='prefix\n'
  case "$kind" in
    actual) # The caller's checked read of an unset actual fails first.
      routines='PROCEDURE take(n: INTEGER); BEGIN END;'
      body='{$INITCK+} take(u)'
      err='local u'; site='9|u)' ;;
    formal) # An unchecked unset actual reaches a checked read in the callee.
      routines='PROCEDURE take(n: INTEGER); BEGIN {$INITCK+} WRITELN(n) {$INITCK-} END;'
      body='take(u)'
      err='parameter n'; site='2|n)' ;;
    formalcopy) # Copying the formal propagates its unset state.
      routines='PROCEDURE take(n: INTEGER); VAR t: INTEGER; BEGIN t := n; {$INITCK+} WRITELN(t) {$INITCK-} END;'
      body='take(u)'
      err='local t'; site='2|t)' ;;
    endresult) # The closing END is the fallthrough return's read site.
      routines='FUNCTION f: INTEGER; BEGIN {$INITCK+} END {$INITCK-};'
      body='x := f'
      err='result of f'; site='2|END {' ;;
    returnresult)
      routines='FUNCTION f(n: INTEGER): INTEGER; BEGIN IF n > 9 THEN f := n; {$INITCK+} RETURN {$INITCK-} END;'
      body='x := f(1)'
      err='result of f'; site='2|RETURN' ;;
    taintresult) # An unchecked return publishes unset state into the caller.
      routines='FUNCTION f: INTEGER; VAR t: INTEGER; BEGIN f := t END;'
      body='x := f; {$INITCK+} WRITELN(x)'
      err='local x'; site='9|x)' ;;
    partial) # Assigned on one path only: unset on the other.
      routines='FUNCTION f(n: INTEGER): INTEGER; BEGIN IF n > 0 THEN f := n {$INITCK+} END {$INITCK-};'
      body='WRITELN(f(1)); x := f(0)'; prefix='prefix\n1\n'
      err='result of f'; site='2|END {' ;;
    recursion) # Each activation's result starts unset.
      routines='FUNCTION f(n: INTEGER): INTEGER; BEGIN IF n > 0 THEN f := f(n - 1) {$INITCK+} END {$INITCK-};'
      body='x := f(2)'
      err='result of f'; site='2|END {' ;;
    nested) # Slots are published only after all actuals are evaluated, so an
            # inner call cannot cross the outer call's argument states.
      routines='FUNCTION id(n: INTEGER): INTEGER; BEGIN id := n END; PROCEDURE pair(a, b: INTEGER); BEGIN {$INITCK+} WRITELN(a); WRITELN(b) {$INITCK-} END;'
      body='pair(id(1), id(u))'; prefix='prefix\n1\n'
      err='parameter b'; site='2|b)' ;;
  esac
  cat > "$work/bad.pas" <<PAS
PROGRAM bad;
$routines
PROCEDURE probe;
VAR $locals;
BEGIN
  {\$INITCK+}
  WRITELN('prefix');
  {\$INITCK-}
  $body;
  WRITELN('after')
END;
BEGIN probe END.
PAS
  # The reported column is the consuming token's: the last match of the
  # needle on the given line of the generated source.
  col=$(python3 - "$work/bad.pas" "$site" <<'PY'
import sys
path, site = sys.argv[1:]
line, needle = site.split('|', 1)
print(open(path).read().splitlines()[int(line) - 1].rindex(needle) + 1)
PY
)
  expect_fail bad "$prefix" "runtime error: INITCK uninitialized $err at line ${site%%|*} column $col"
done

# O0 side channel shape: the callee copies and clears its slot before any
# call; the caller publishes after evaluating every actual, clears after the
# call, resets the result flag first and collects it after.
cat > "$work/channel.pas" <<'PAS'
PROGRAM channel;
FUNCTION f(n: INTEGER; r: REAL): INTEGER;
BEGIN WRITELN(r:3:1); f := n END;
PROCEDURE probe;
VAR x: INTEGER;
BEGIN x := f(f(1, 2.0), 3.0) END;
BEGIN probe END.
PAS
bin/pascal1981 -O0 -S "$work/channel.pas" -o "$work/channel.ll"
python3 - "$work/channel.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
assert '@pas_initck_args = external thread_local global [16 x ptr]' in ir
assert '@pas_initck_ret = external thread_local global i1' in ir
callee = ir[ir.index('define i16 @f('):]
callee = callee[:callee.index('\n}')]
recv = callee.index('%initck.arg = load ptr, ptr @pas_initck_args')
clear = callee.index('store ptr null, ptr @pas_initck_args', recv)
first_call = callee.index('call ')
assert recv < clear < first_call
assert 'select i1' in callee[clear:first_call]
# Only the tracked INTEGER formal is received; REAL r has no slot.
assert callee.count('@pas_initck_args') == 2 and not re.search(r'%initck\.r[ ,]', callee)
assert re.search(r'store i1 %initck\.result\d*, ptr @pas_initck_ret', callee)
probe = ir[ir.index('define void @probe('):]
probe = probe[:probe.index('\n}')]
calls = [m.start() for m in re.finditer(r'call i16 @f\(', probe)]
assert len(calls) == 2
prev = 0
for at in calls:
    window = probe[prev:at]  # since the previous call (or entry)
    pub = re.findall(r'store ptr (%initck\.actual\d*), ptr @pas_initck_args', window)
    assert len(pub) == 1, window  # one tracked actual, published once
    # The actual's state is stored, then published, then the flag reset.
    publish = window.index(f'store ptr {pub[0]}, ptr @pas_initck_args')
    assert re.search(r'store i1 [^,]+, ptr ' + re.escape(pub[0]) + ',', window[:publish])
    assert window.rindex('store i1 true, ptr @pas_initck_ret') > publish
    after = probe[at:]
    clear = after.index('store ptr null, ptr @pas_initck_args')
    assert clear < after.index('load i1, ptr @pas_initck_ret')
    prev = at + 1
# The inner call's result state feeds the outer actual's accumulator.
inner, outer = calls
seg = probe[inner:outer]
assert re.search(r'%initck\.returned\d* = load i1, ptr @pas_initck_ret', seg)
PY

# --- VAR/CONST formals share the caller's storage state. ---
# Binding is not a read; callee writes initialize the caller's slot, callee
# reads check it, forwarding keeps the original binding, and two formals bound
# to one local share it. Storage outside the slice (a global) binds a private
# initialized slot. An address-escaped VAR formal releases its caller's slot
# as initialized (written by untracked effects here). fillc is a plain EXTERN
# implemented in C: it receives a published slot it never clears, so the
# caller-side clear must keep the following call's channel clean.
cat > "$work/var-ok.pas" <<'PAS'
PROGRAM varok;
VAR g: INTEGER;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
{$INITCK+}
PROCEDURE setit(VAR n: INTEGER; k: INTEGER); BEGIN n := k END;
PROCEDURE bump(VAR n: INTEGER); BEGIN n := n + 1 END;
PROCEDURE fwd(VAR n: INTEGER); BEGIN setit(n, -32768) END;
PROCEDURE copyit(VAR dst: INTEGER; CONST src: INTEGER); BEGIN dst := src END;
PROCEDURE swap(VAR a, b: INTEGER); VAR t: INTEGER; BEGIN t := a; a := b; b := t END;
PROCEDURE flags(VAR b: BOOLEAN; VAR c: CHAR); BEGIN b := NOT b; c := 'z' END;
PROCEDURE third(a, b: INTEGER; c: CHAR); BEGIN WRITELN(a + b, c) END;
PROCEDURE show(CONST c: INTEGER); BEGIN WRITELN(c) END;
{$INITCK-}
PROCEDURE zap(VAR n: INTEGER); BEGIN fillc(ADR n, 2, CHR(0)) END;
{$INITCK+}
PROCEDURE probe;
VAR x, y, u: INTEGER; b: BOOLEAN; c, w: CHAR;
BEGIN
  setit(x, 1); bump(x); fwd(y); WRITELN(x, ' ', y);
  copyit(u, x); swap(u, y); WRITELN(u, ' ', y);
  swap(x, x); bump(x); WRITELN(x);
  b := FALSE; flags(b, c); WRITELN(ORD(b), c);
  g := 7; bump(g); show(g); setit(g, 1); bump(g); show(g);
  zap(x); WRITELN(x);
  {$INITCK-} fillc(ADR g, 2, w); {$INITCK+} third(1, 2, 'A')
END;
BEGIN probe END.
{$INITCK-}
PAS
expect_ok var-ok '2 -32768\n-32768 2\n3\n1z\n8\n2\n0\n3A\n'

for kind in varread constread varcopy forward partial; do
  routines=''; locals='u, x, y: INTEGER'; body=''; prefix='prefix\n'
  case "$kind" in
    varread) # A checked read through VAR finds the caller's slot unset.
      routines='PROCEDURE bump(VAR n: INTEGER); BEGIN {$INITCK+} n := n + 1 {$INITCK-} END;'
      body='bump(u)'; err='parameter n'; site='2|n +' ;;
    constread)
      routines='PROCEDURE show(CONST c: INTEGER); BEGIN {$INITCK+} WRITELN(c) {$INITCK-} END;'
      body='show(u)'; err='parameter c'; site='2|c)' ;;
    varcopy) # An unchecked copy through CONST/VAR carries unset state home.
      routines='PROCEDURE copyit(VAR dst: INTEGER; CONST src: INTEGER); BEGIN dst := src END;'
      body='copyit(y, u); {$INITCK+} WRITELN(y)'; err='local y'; site='9|y)' ;;
    forward) # Forwarding a VAR formal keeps the original caller binding.
      routines='PROCEDURE bump(VAR n: INTEGER); BEGIN {$INITCK+} n := n + 1 {$INITCK-} END; PROCEDURE fwd(VAR m: INTEGER); BEGIN bump(m) END;'
      body='fwd(u)'; err='parameter n'; site='2|n +' ;;
    partial) # Written on one path only: the caller's slot stays unset.
      routines='PROCEDURE maybe(VAR n: INTEGER; doit: BOOLEAN); BEGIN IF doit THEN n := 1 END;'
      body='maybe(x, TRUE); maybe(y, FALSE); {$INITCK+} WRITELN(x); WRITELN(y)'
      prefix='prefix\n1\n'; err='local y'; site='9|y)' ;;
  esac
  cat > "$work/bad.pas" <<PAS
PROGRAM bad;
$routines
PROCEDURE probe;
VAR $locals;
BEGIN
  {\$INITCK+}
  WRITELN('prefix');
  {\$INITCK-}
  $body;
  WRITELN('after')
END;
BEGIN probe END.
PAS
  col=$(python3 - "$work/bad.pas" "$site" <<'PY'
import sys
path, site = sys.argv[1:]
line, needle = site.split('|', 1)
print(open(path).read().splitlines()[int(line) - 1].rindex(needle) + 1)
PY
)
  expect_fail bad "$prefix" "runtime error: INITCK uninitialized $err at line ${site%%|*} column $col"
done

# O0 shape: a tracked VAR actual publishes the caller's own state slot (no
# temporary), a global actual publishes nothing, and the callee guards and
# writes through the selected binding.
cat > "$work/var-ir.pas" <<'PAS'
PROGRAM varir;
VAR g: INTEGER;
PROCEDURE bump(VAR n: INTEGER); BEGIN {$INITCK+} n := n + 1 {$INITCK-} END;
PROCEDURE probe;
VAR x: INTEGER;
BEGIN x := 1; bump(x); bump(g) END;
BEGIN probe END.
PAS
bin/pascal1981 -O0 -S "$work/var-ir.pas" -o "$work/var-ir.ll"
python3 - "$work/var-ir.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
probe = ir[ir.index('define void @probe('):]
probe = probe[:probe.index('\n}')]
assert probe.count('store ptr %initck.x, ptr @pas_initck_args') == 1
assert len(re.findall(r'store ptr %[^,]+, ptr @pas_initck_args', probe)) == 1  # none for g
assert '%initck.actual' not in probe
callee = ir[ir.index('define void @bump('):]
callee = callee[:callee.index('\n}')]
assert re.search(r'%initck\.n\.ref = select i1 %\d+, ptr %initck\.n, ptr %initck\.arg', callee)
guard = callee.index('load i1, ptr %initck.n.ref')
data = callee.index('load i16, ptr %0')
assert guard < data
assert re.search(r'store i1 [^,]+, ptr %initck\.n\.ref,', callee[data:])
PY

# --- Nested routines, captures and WITH. ---
# A nested routine that redeclares a name (formal or local, at any depth) owns
# separate storage, so the enclosing local stays tracked. Inside a WITH body a
# name that is not a field of a target with an evident record type (a
# zero-selector symbol, VAR record formals included) is still the routine's
# own tracked slot; a same-name field shadows it without touching it.
cat > "$work/scope-ok.pas" <<'PAS'
PROGRAM scopeok;
TYPE R = RECORD f, g: INTEGER END;
{$INITCK+}
PROCEDURE outer(k: INTEGER; VAR vr: R);
VAR x, f, u: INTEGER; r, s: R; b: BOOLEAN;
  PROCEDURE inner(x: INTEGER);
  VAR k: INTEGER;
    FUNCTION deeper(k: INTEGER): INTEGER;
    VAR x: INTEGER;
    BEGIN x := k * 2; deeper := x END;
  BEGIN k := deeper(x); WRITELN(k) END;
BEGIN
  {$INITCK-} r.f := 10; r.g := 20; s.g := 5; f := 3; {$INITCK+}
  WITH r DO BEGIN x := {$INITCK-} g {$INITCK+} + k; f := 11 END;
  WITH r, s DO BEGIN u := x + 1; b := u > x END;
  WITH vr DO BEGIN x := x + 100; g := x END;
  WRITELN(x, ' ', f, ' ', u, ' ', ORD(b));
  inner(x)
END;
{$INITCK-}
VAR rec: R;
BEGIN outer(1, rec); WRITELN(rec.g) END.
PAS
expect_ok scope-ok '121 3 22 1\n242\n121\n'

for kind in withread nestedread nestedother; do
  case "$kind" in
    withread) # A checked read inside a WITH body is the routine's local.
      routines='TYPE R = RECORD f: INTEGER END;'; locals='u, x, y: INTEGER; r: R'
      body='r.f := 1; WITH r DO BEGIN {$INITCK+} WRITELN(u) {$INITCK-} END'
      err='local u'; site='9|u)' ;;
    nestedread) # The nested routine's own same-name local starts unset.
      routines='PROCEDURE inner; VAR x: INTEGER; BEGIN {$INITCK+} WRITELN(x) {$INITCK-} END;'
      locals='u, x, y: INTEGER'; body='x := 1; inner'
      err='local x'; site='2|x)' ;;
    nestedother) # ...and initializing it leaves the enclosing x unset.
      routines='PROCEDURE inner(x: INTEGER); VAR y: INTEGER; BEGIN y := x END;'
      locals='u, x, y: INTEGER'; body='inner(1); {$INITCK+} WRITELN(x)'
      err='local x'; site='9|x)' ;;
  esac
  # Nested routines must live inside probe to exercise nesting.
  if [ "$kind" = withread ]; then decls=''; else decls="$routines"; routines=''; fi
  cat > "$work/bad.pas" <<PAS
PROGRAM bad;
$routines
PROCEDURE probe;
VAR $locals;
$decls
BEGIN
  {\$INITCK+}
  WRITELN('prefix');
  {\$INITCK-}
  $body;
  WRITELN('after')
END;
BEGIN probe END.
PAS
  # Drop whichever slot is empty, so the body is line 9 either way and a
  # nested declaration is line 4.
  python3 - "$work/bad.pas" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
if lines[1] == '':
    del lines[1]
else:
    del lines[4]
open(p, 'w').write('\n'.join(lines) + '\n')
PY
  if [ "$kind" != withread ]; then site="${site/#2|/4|}"; fi
  col=$(python3 - "$work/bad.pas" "$site" <<'PY'
import sys
path, site = sys.argv[1:]
line, needle = site.split('|', 1)
print(open(path).read().splitlines()[int(line) - 1].rindex(needle) + 1)
PY
)
  expect_fail bad 'prefix\n' "runtime error: INITCK uninitialized $err at line ${site%%|*} column $col"
done

# Captures: without a static link this compiler cannot lower a nested
# routine's reference to an enclosing local at all. An enabled read reports
# the INITCK boundary before lowering; disabled, the pre-existing compiler
# limitation remains, and INITCK adds nothing to it.
cat > "$work/capture.pas" <<'PAS'
PROGRAM capture;
PROCEDURE outer;
VAR x: INTEGER;
  PROCEDURE inner; BEGIN {$INITCK+} WRITELN(x) {$INITCK-} END;
BEGIN x := 1; inner END;
BEGIN outer END.
PAS
if bin/pascal1981 -O0 -S "$work/capture.pas" -o "$work/capture.ll" 2> "$work/err"; then
  echo 'FAIL: enabled capture accepted' >&2; exit 1
fi
printf 'INITCK unsupported boundary: global or captured storage\n' > "$work/expected-err"
sed -E 's/ at line [0-9]+ column [0-9]+$//' "$work/err" | diff -u "$work/expected-err" -
sed -i 's/{\$INITCK+}/{$INITCK-}/' "$work/capture.pas"
if bin/pascal1981 -O0 -S "$work/capture.pas" -o "$work/capture.ll" 2> "$work/err"; then
  echo 'FAIL: capture unexpectedly supported; revisit INITCK capture coverage' >&2; exit 1
fi
test -s "$work/err"
! grep -q INITCK "$work/err"

# --- Uninstrumented C on either side of the side channel (executed). ---
# drive (C) calls the Pascal probe_cb with nothing published: its formal is
# initialized. csink, a C-implemented plain EXTERN, receives a published
# unset slot it never clears; the caller's clear keeps that stale pointer from
# reaching probe_cb's slot 1. cvalue, a C-implemented INTEGER function, cannot
# publish a result state: the caller's reset must make it initialized even
# right after a Pascal function published an unset result. A [C] routine's
# value actual is an ordinary caller read: checked when enabled.
cat > "$work/cside.c" <<'C'
#include <stdint.h>
void probe_cb(int16_t n);
void csink(int16_t n) { (void) n; }
void csinkc(int16_t n) { (void) n; }
int16_t cvalue(void) { return 42; }
void drive(void) { probe_cb(7); }
C
cat > "$work/cinterop.pas" <<'PAS'
PROGRAM cinterop;
FUNCTION cvalue: INTEGER; EXTERN;
PROCEDURE csink(n: INTEGER); EXTERN;
PROCEDURE csinkc(n: INTEGER) [C]; EXTERN;
PROCEDURE drive; EXTERN;
PROCEDURE probe_cb(n: INTEGER); BEGIN {$INITCK+} WRITELN(n) {$INITCK-} END;
FUNCTION unsetres: INTEGER; BEGIN END;
PROCEDURE probe(bad: BOOLEAN);
VAR x, y, u: INTEGER;
BEGIN
  y := unsetres; x := cvalue;
  {$INITCK+} WRITELN(x); {$INITCK-}
  csink(u); drive;
  IF bad THEN BEGIN {$INITCK+} csinkc(u) {$INITCK-} END;
  WRITELN('after')
END;
BEGIN probe(FALSE); probe(TRUE) END.
PAS
for opt in 0 2; do
  bin/pascal1981 --dialect extended -O"$opt" -S "$work/cinterop.pas" -o "$work/cinterop.ll"
  clang -O"$opt" "$work/cinterop.ll" "$work/cside.c" runtime/build/libpascalrt.a -lm -o "$work/cinterop"
  status=0
  { "$work/cinterop" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
  test "$status" -ne 0
  printf '42\n7\nafter\n42\n7\n' > "$work/expected"
  diff -u "$work/expected" "$work/actual"
  col=$(( $(sed -n 14p "$work/cinterop.pas" | grep -bo 'u)' | tail -1 | cut -d: -f1) + 1 ))
  printf 'runtime error: INITCK uninitialized local u at line 14 column %s\n' "$col" > "$work/expected-err"
  diff -u "$work/expected-err" "$work/err"
done

# --- Return read sites follow ordinary directive/legacy rules. ---
# DEBUG+ at the closing END enables the fallthrough check; PUSH/POP restores
# a disabled END; a RETURN inside an enabled PUSH region is checked.
cat > "$work/sites-ok.pas" <<'PAS'
PROGRAM sitesok;
FUNCTION restored: INTEGER; BEGIN {$PUSH} {$INITCK+} {$POP} END;
FUNCTION assigned(n: INTEGER): INTEGER;
BEGIN assigned := n; {$PUSH} {$INITCK+} RETURN {$POP} END;
BEGIN WRITELN(restored, ' ', assigned(3)) END.
PAS
expect_ok sites-ok '0 3\n'
for kind in debugend pushreturn; do
  case "$kind" in
    debugend) fn='FUNCTION f: INTEGER; BEGIN {$DEBUG+} END {$DEBUG-};'; needle='END' ;;
    pushreturn) fn='FUNCTION f: INTEGER; BEGIN {$PUSH} {$INITCK+} RETURN {$POP} END;'; needle='RETURN' ;;
  esac
  printf 'PROGRAM sitebad;\n%s\nBEGIN WRITELN(%s); WRITELN(f) END.\n' "$fn" "'prefix'" > "$work/site-bad.pas"
  col=$(( $(sed -n 2p "$work/site-bad.pas" | grep -bo "$needle" | head -1 | cut -d: -f1) + 1 ))
  expect_fail site-bad 'prefix\n' "runtime error: INITCK uninitialized result of f at line 2 column $col"
done
# Legacy ASTs without return read-site snapshots opt out exactly like other
# read sites: no guard, the default bytes return, the program succeeds.
printf 'PROGRAM legacyret;\nFUNCTION f: INTEGER;\nBEGIN IF FALSE THEN f := 1; {$INITCK+} RETURN {$INITCK-} END;\nFUNCTION g: INTEGER; BEGIN {$INITCK+} END {$INITCK-};\nBEGIN WRITELN(f, g) END.\n' > "$work/legacyret.pas"
bin/lexer < "$work/legacyret.pas" | bin/parser | bin/typechecker > "$work/legacyret.json"
python3 - "$work/legacyret.json" > "$work/legacyret-stripped.json" <<'PY'
import json, sys
tree = json.load(open(sys.argv[1]))
stripped = 0
def walk(v):
    global stripped
    if isinstance(v, dict):
        if v.get('__node_type__') in ('ReturnStmt', 'Block') and v.get('read_flags', {}).get('INITCK'):
            del v['read_flags']; stripped += 1
        for x in v.values(): walk(x)
    elif isinstance(v, list):
        for x in v: walk(x)
walk(tree)
assert stripped == 2
json.dump(tree, sys.stdout)
PY
bin/codegen < "$work/legacyret-stripped.json" > "$work/legacyret.ll"
! grep -q 'pas_initck_fail' "$work/legacyret.ll"
clang "$work/legacyret.ll" runtime/build/libpascalrt.a -lm -o "$work/legacyret"
"$work/legacyret" > "$work/actual"
printf '00\n' | diff -u - "$work/actual"
bin/codegen < "$work/legacyret.json" | grep -c 'call void @pas_initck_fail' | grep -qx 2

# --- VAR bindings survive recursion. ---
cat > "$work/recvar-ok.pas" <<'PAS'
PROGRAM recvarok;
{$INITCK+}
PROCEDURE fill(VAR n: INTEGER; d: INTEGER);
BEGIN IF d = 0 THEN n := 5 ELSE BEGIN fill(n, d - 1); n := n + 1 END END;
PROCEDURE probe; VAR x: INTEGER; BEGIN fill(x, 3); WRITELN(x) END;
BEGIN probe END.
{$INITCK-}
PAS
expect_ok recvar-ok '8\n'
printf 'PROGRAM recvarbad;\nPROCEDURE fill(VAR n: INTEGER; d: INTEGER);\nBEGIN IF d > 9 THEN n := 5 ELSE IF d > 0 THEN fill(n, d - 1) END;\nPROCEDURE probe; VAR x: INTEGER; BEGIN fill(x, 3); {$INITCK+} WRITELN(x) {$INITCK-} END;\nBEGIN WRITELN(%s); probe END.\n' "'prefix'" > "$work/recvar-bad.pas"
col=$(( $(sed -n 4p "$work/recvar-bad.pas" | grep -bo 'x)' | tail -1 | cut -d: -f1) + 1 ))
expect_fail recvar-bad 'prefix\n' "runtime error: INITCK uninitialized local x at line 4 column $col"
echo 'PASS: INITCK routine boundaries: values/defaults/signatures, formals, results, C interop, read sites, nesting and WITH'
