#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# INITCK pointers and heap storage: a plain typed pointer's or descriptor's
# value is one tracked leaf, NEW initializes only the destination pointer,
# and reading a pointer to reach its referent (a DEREF, DISPOSE, UPPER) is a
# read of the pointer. NEW referents and SUPER ARRAY elements carry per-leaf
# state owned by the allocation (runtime/initck_heap.c). Never run unchecked
# bad reads as if their output meant anything.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ulimit -c 0

# expect_ok NAME EXPECTED-STDOUT [DIALECTS]: O0/O2, INITCK as written; both
# dialects unless the program needs the extended one ([C] routines).
expect_ok() {
  local name=$1 expected=$2 dialects=${3:-vintage extended}
  printf '%b' "$expected" > "$work/$name.expected"
  for dialect in $dialects; do
    for opt in 0 2; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/$name.pas" -o "$work/$name" 2> "$work/err"
      # UNSAFERAW/UNSAFESUPER always warn; nothing else may be printed.
      sed -i '/^warning: unsafe-super-array-conversion$/d' "$work/err"
      test ! -s "$work/err"
      "$work/$name" > "$work/actual" 2> "$work/err"
      diff -u "$work/$name.expected" "$work/actual"
      test ! -s "$work/err"
    done
  done
}

# expect_fail NAME STDOUT-PREFIX ERROR-LINE: exactly one INITCK error, O0/O2.
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

# expect_boundary NAME CATEGORY: rejected at O0/O2 with exactly one diagnostic
# and no IR; the INITCK- twin compiles cleanly (and is never run).
expect_boundary() {
  local name=$1 category=$2
  sed 's/{\$INITCK+}/{$INITCK-}/g' "$work/$name.pas" > "$work/$name-off.pas"
  bin/pascal1981 -O0 -S "$work/$name-off.pas" -o "$work/$name-off.ll" 2> "$work/err"
  test ! -s "$work/err"
  printf 'INITCK unsupported boundary: %s\n' "$category" > "$work/expected-err"
  for opt in 0 2; do
    rm -f "$work/$name.ll"
    if bin/pascal1981 -O"$opt" -S "$work/$name.pas" -o "$work/$name.ll" 2> "$work/err"; then
      echo "FAIL: $name boundary accepted" >&2; exit 1
    fi
    sed -E 's/ at line [0-9]+ column [0-9]+$//' "$work/err" | diff -u "$work/expected-err" -
    test ! -s "$work/$name.ll"
  done
}

# at NAME LINE TEXT: 1-based column of the first TEXT on LINE of NAME.pas.
at() {
  local col
  col=$(sed -n "$2p" "$work/$1.pas" | grep -bo -F -- "$3" | head -1 | cut -d: -f1)
  echo "line $2 column $((col + 1))"
}

# --- Pointer values: producers, copies, comparisons, formals, results. ---
cat > "$work/ptr-ok.pas" <<'PAS'
PROGRAM ptrok;
TYPE PR = ^R;
     R = RECORD v: INTEGER; next: PR END;
     Holder = RECORD head: PR; n: INTEGER END;
VAR g: PR;
PROCEDURE make(VAR p: PR);
BEGIN NEW(p) END;
FUNCTION same(a, b: PR): BOOLEAN;
BEGIN same := a = b END;
FUNCTION fresh: PR;
VAR t: PR;
BEGIN NEW(t); t^.v := 0; t^.next := NIL; fresh := t END;
PROCEDURE probe;
VAR p, q, u: PR; h: Holder; links: ARRAY [1..2] OF PR;
BEGIN
  {$INITCK+}
  NEW(p); q := p;
  IF same(p, q) THEN WRITELN('same');
  q := NIL;
  IF q = NIL THEN WRITELN('nil');
  p^.v := 3; p^.next := NIL;
  make(u); u^.next := p;
  h.head := fresh; h.n := 1;
  NEW(h.head^.next); h.head^.next^.next := NIL;
  links[1] := u; links[2] := links[1]^.next;
  IF links[2] = p THEN WRITELN('linked');
  {$INITCK-} g := u; {$INITCK+}
  q := u^.next;
  DISPOSE(q); DISPOSE(u); DISPOSE(h.head^.next); DISPOSE(h.head);
  WRITELN('done')
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok ptr-ok 'same\nnil\nlinked\ndone\n'

# An unset pointer fails at every kind of read, named like any tracked
# storage; a DEREF reports the coordinates of its `^`.
for kind in compare deref selected dispose disposefield copy branch formal result; do
  pre=''; decl='p: PR'; body="IF p = NIL THEN WRITELN('nil')"; extra=''
  what='local p'; line=9; needle='p = NIL'; prefix='prefix\n'
  case "$kind" in
    deref) body='p^.v := 1'; needle='^' ;;
    selected) decl='h: RECORD n: INTEGER; head: PR END'; body='h.n := 1; h.head^.v := 1'
      what='component h.head'; needle='^' ;;
    dispose) body='DISPOSE(p)'; needle='p)' ;;
    disposefield) decl='a: ARRAY [1..2] OF PR'; body='NEW(a[1]); DISPOSE(a[2])'
      what='component a[2]'; needle='a[2]' ;;
    # An unchecked copy carries the source pointer's state.
    copy) decl='p, q: PR'; pre='q := p;'; body="IF q = NIL THEN WRITELN('nil')"
      what='local q'; needle='q = NIL' ;;
    branch) decl='p: PR; k: INTEGER'; pre='k := 0; IF k = 1 THEN NEW(p);' ;;
    # An unset pointer reaches a callee unchecked and fails at its read.
    formal) extra='PROCEDURE use(f: PR); BEGIN {$INITCK+} IF f = NIL THEN WRITELN(1) {$INITCK-} END;'
      pre='use(p);'; body="WRITELN('unreached')"; what='parameter f'; line=5; needle='f = NIL' ;;
    result) extra='FUNCTION unset: PR; BEGIN {$INITCK-} WRITELN(0) {$INITCK+} END {$INITCK-};'
      pre='p := unset;'; body="WRITELN('unreached')"; what='result of unset'; line=5; needle='END'
      prefix='prefix\n0\n' ;;
  esac
  cat > "$work/ptr-bad.pas" <<PAS
PROGRAM ptrbad;
TYPE PR = ^R;
     R = RECORD v: INTEGER; next: PR END;
PROCEDURE probe;
$extra
VAR $decl;
BEGIN
  WRITELN('prefix'); $pre
  {\$INITCK+} $body; {\$INITCK-}
  WRITELN('after')
END;
BEGIN probe END.
PAS
  expect_fail ptr-bad "$prefix" "runtime error: INITCK uninitialized $what at $(at ptr-bad "$line" "$needle")"
done

# The pointer guard precedes the native pointer load; NEW publishes the
# destination pointer's state after storing the pointer.
cat > "$work/ptr-ir.pas" <<'PAS'
PROGRAM ptrir;
TYPE PR = ^R;
     R = RECORD v: INTEGER; next: PR END;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); {$INITCK+} p^.v := 1 {$INITCK-} END;
BEGIN probe END.
PAS
bin/pascal1981 -O0 -S "$work/ptr-ir.pas" -o "$work/ptr-ir.ll"
python3 - "$work/ptr-ir.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
new = f.index('call ptr @malloc')
store = f.index('store ptr ', new)
publish = f.index('store i1 true, ptr %initck.p,', store)
ready = f.index('load i1, ptr %initck.p', publish)
fail = f.index('call void @pas_initck_error', ready)
load = f.index('load ptr, ptr %p', ready)
assert fail < load, 'pointer guard must precede the pointer load'
print('PASS: pointer guard order and NEW publication')
PY

# --- Heap referents of ordinary NEW: per-leaf state keyed by allocation. ---
# NEW initializes the pointer only; every leaf of the referent starts unset
# and is initialized by exactly the writes it receives, through any pointer
# to it (state belongs to the allocation, not to a name).
cat > "$work/heap-ok.pas" <<'PAS'
PROGRAM heapok;
TYPE PR = ^R;
     Pair = RECORD a, b: INTEGER END;
     R = RECORD v, w: INTEGER; c: CHAR; ok: BOOLEAN; next: PR;
                inner: Pair; row: ARRAY [1..3] OF CHAR END;
     PI = ^INTEGER;
     PA = ^ARRAY [1..4] OF INTEGER;
PROCEDURE setv(VAR x: INTEGER; n: INTEGER);
BEGIN x := n END;
PROCEDURE swap(VAR x, y: INTEGER);
VAR t: INTEGER;
BEGIN t := x; x := y; y := t END;
FUNCTION total(p: Pair): INTEGER;
BEGIN total := p.a + p.b END;
PROCEDURE probe(k: INTEGER);
VAR p, q, head: PR; ip: PI; ap: PA; i, sum: INTEGER; r: Pair;
BEGIN
  {$INITCK+}
  NEW(p); p^.v := 0; p^.next := NIL; p^.c := 'h'; p^.ok := FALSE;
  ip := NIL; NEW(ip); ip^ := -32768;
  NEW(ap); FOR i := 1 TO 4 DO ap^[i] := i * k;
  WRITELN(p^.v, ' ', ip^, ' ', ap^[k + 1], ' ', p^.c, ORD(p^.ok), ' ', p^.next = NIL);
  { A linked list built and walked with every read checked. }
  head := NIL;
  FOR i := 1 TO 3 DO BEGIN NEW(q); q^.v := i; q^.next := head; head := q END;
  sum := 0; q := head;
  WHILE q <> NIL DO BEGIN sum := sum + q^.v; q := q^.next END;
  WRITELN('sum ', sum);
  { Another pointer to the same referent shares its state. }
  q := p; q^.w := 7; WRITELN(p^.w);
  { Producers: WITH-bound fields, VAR bindings, nested components. }
  WITH p^ DO BEGIN inner.a := v + 1; row[2] := c END;
  setv(p^.inner.b, 5); swap(p^.inner.a, p^.inner.b);
  WRITELN(p^.inner.a, ' ', p^.inner.b, ' ', p^.row[2]);
  { Whole copies and value actuals of fully written heap aggregates. }
  r := p^.inner; NEW(q); q^.inner := r; q^.inner := p^.inner;
  WRITELN(total(q^.inner), ' ', total(p^.inner));
  DISPOSE(p); DISPOSE(ip); DISPOSE(ap)
  {$INITCK-}
END;
BEGIN probe(1); probe(3) END.
PAS
expect_ok heap-ok '0 -32768 2 h0 TRUE\nsum 6\n7\n5 1 h\n6 6\n0 -32768 12 h0 TRUE\nsum 6\n7\n5 1 h\n6 6\n'

# A disabled write still initializes its leaf, and an unchecked partial
# copy carries per-leaf state into another referent.
cat > "$work/heap-copy.pas" <<'PAS'
PROGRAM heapcopy;
TYPE Pair = RECORD a, b: INTEGER END;
     PP = ^Pair;
PROCEDURE probe;
VAR p, q: PP;
BEGIN
  NEW(p); NEW(q);
  {$INITCK-} p^.a := 4; q^ := p^; {$INITCK+}
  WRITELN(q^.a)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok heap-copy '4\n'

for kind in fresh sibling ptrfield renew alias array scalar with var whole partial taint; do
  decl='p: PR'; pre='NEW(p)'; body='WRITELN(p^.v)'; what='component p^.v'; needle='p^.v'
  extra=''; line=10
  case "$kind" in
    sibling) pre='NEW(p); p^.v := 1'; body='WRITELN(p^.w)'; what='component p^.w'; needle='p^.w' ;;
    # An unset pointer stored in a referent fails at its own `^`.
    ptrfield) body='p^.next^.v := 1'; what='component p^.next'; needle='^.v' ;;
    # Each NEW gives a fresh referent, whatever the pointer held before.
    renew) pre='NEW(p); p^.v := 1; NEW(p)' ;;
    alias) decl='p, q: PR'; pre='NEW(p); q := p; q^.v := 1'; body='WRITELN(q^.v, p^.w)'
      what='component p^.w'; needle='p^.w' ;;
    array) decl='a: PA'; pre='NEW(a); a^[1] := 1'; body='WRITELN(a^[2])'; what='component a^[2]'; needle='a^[2]' ;;
    scalar) decl='i: PI'; pre='NEW(i)'; body='WRITELN(i^)'; what='component i^'; needle='i^' ;;
    with) pre='NEW(p); p^.v := 1'; body='WITH p^ DO WRITELN(v, w)'; what='field w'; needle='w)' ;;
    var) extra='PROCEDURE show(VAR x: INTEGER); BEGIN {$INITCK+} WRITELN(x) {$INITCK-} END;'
      body='show(p^.w)'; what='parameter x'; line=6; needle='x)' ;;
    whole) decl='p: PR; r: R'; pre='NEW(p); p^.v := 1'; body='r := p^'; what='part of p^'; needle='p^;' ;;
    partial) decl='p, q: PR'; pre='NEW(p); NEW(q); p^.v := 1; q^ := p^'; body='WRITELN(q^.v, q^.w)'
      what='component q^.w'; needle='q^.w' ;;
    # An unchecked read of an unset heap leaf taints its destination.
    taint) decl='p: PR; x: INTEGER'; pre='NEW(p); x := p^.w + 0'; body='WRITELN(x)'
      what='local x'; needle='x)' ;;
  esac
  cat > "$work/heap-bad.pas" <<PAS
PROGRAM heapbad;
TYPE PR = ^R;
     R = RECORD v, w: INTEGER; next: PR END;
     PA = ^ARRAY [1..2] OF INTEGER;
     PI = ^INTEGER;
$extra
PROCEDURE probe;
VAR $decl;
BEGIN $pre; WRITELN('prefix');
  {\$INITCK+} $body; {\$INITCK-}
  WRITELN('after')
END;
BEGIN probe END.
PAS
  expect_fail heap-bad 'prefix\n' "runtime error: INITCK uninitialized $what at $(at heap-bad "$line" "$needle")"
done

# Storage outside the model reads as initialized and is never a false
# positive: memory from C, and a referent released because its address
# reached an unmodeled effect (a WITH-bound field's ADR, a conversion to
# ADRMEM, an ADRMEM actual), written there by C.
cat > "$work/heap-foreign.pas" <<'PAS'
PROGRAM heapforeign;
TYPE R = RECORD c1, c2: CHAR END;
     PR = ^R;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE probe;
VAR p: PR; a: ADRMEM;
BEGIN
  p := malloc(2); p^.c1 := 'f'; p^.c2 := 'g';
  {$INITCK+} WRITELN(p^.c1, p^.c2); {$INITCK-}
  NEW(p); WITH p^ DO fillc(ADR c1, 2, 'z');
  {$INITCK+} WRITELN(p^.c1, p^.c2); {$INITCK-}
  NEW(p); a := p; fillc(a, 2, 'y');
  {$INITCK+} WRITELN(p^.c1, p^.c2); {$INITCK-}
  NEW(p); fillc(p, 2, 'x');
  {$INITCK+} WRITELN(p^.c1, p^.c2) {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok heap-foreign 'fg\nzz\nyy\nxx\n' extended

# A [C] routine receiving a pointer releases its referent (executed: C
# writes the fields Pascal then reads checked).
cat > "$work/cset.c" <<'C'
#include <stdint.h>
struct r { int16_t v, w; };
void cset(struct r *p) { p->v = 1; p->w = 2; }
C
cat > "$work/heap-c.pas" <<'PAS'
PROGRAM heapc;
TYPE R = RECORD v, w: INTEGER END;
     PR = ^R;
PROCEDURE cset(p: PR) [C]; EXTERN;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); cset(p); {$INITCK+} WRITELN(p^.v, ' ', p^.w) {$INITCK-} END;
BEGIN probe END.
PAS
for opt in 0 2; do
  bin/pascal1981 --dialect extended -O"$opt" -S "$work/heap-c.pas" -o "$work/heap-c.ll"
  clang -O"$opt" "$work/heap-c.ll" "$work/cset.c" runtime/build/libpascalrt.a -lm -o "$work/heap-c"
  "$work/heap-c" > "$work/actual" 2> "$work/err"
  printf '1 2\n' > "$work/expected"
  diff -u "$work/expected" "$work/actual"
  test ! -s "$work/err"
done

# IR: NEW records the referent's state after the allocation and before the
# pointer is published; a checked heap read looks the state up after the
# pointer load and branches on it before the native load.
cat > "$work/heap-ir.pas" <<'PAS'
PROGRAM heapir;
TYPE R = RECORD v, w: INTEGER END;
     PR = ^R;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); p^.v := 1; {$INITCK+} WRITELN(p^.w) {$INITCK-} END;
BEGIN probe END.
PAS
bin/pascal1981 -O0 -S "$work/heap-ir.pas" -o "$work/heap-ir.ll"
python3 - "$work/heap-ir.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
alloc = f.index('call ptr @malloc(i64 4)')
reg = f.index('call void @pas_initck_heap_new(ptr ', alloc)
assert f[reg:].split('\n')[0].endswith(', i64 2)')
store = f.index('store ptr ', reg)
publish = f.index('store i1 true, ptr %initck.p,', store)
read = f.rindex('call ptr @pas_initck_heap_at(ptr ')
assert f.rindex('load ptr, ptr %p', 0, read) > publish
guard = f.index('call void @pas_initck_fail(', read)
load = f.index('load i16, ptr ', read)
assert guard < load, 'heap guard must precede the native load'
print('PASS: heap registration before publication; lookup and guard before load')
PY

# --- SUPER ARRAY descriptors: the {data, upper} value is one leaf. ---
# A descriptor's state is its own, separate from its elements': NEW, an
# import and copies initialize the descriptor; UPPER, comparisons, DISPOSE,
# UNSAFERAW and dereferences read it. SUPER ARRAY needs the extended dialect.
cat > "$work/desc-ok.pas" <<'PAS'
PROGRAM descok;
TYPE Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
     Box = RECORD n: INTEGER; cells: P END;
PROCEDURE grow(VAR d: P; n: INTEGER);
BEGIN NEW(d, n) END;
FUNCTION make(n: INTEGER): P;
VAR t: P;
BEGIN NEW(t, n); make := t END;
FUNCTION top(d: P): INTEGER64;
BEGIN top := UPPER(d^) END;
PROCEDURE probe;
VAR p, q: P; b: Box; raw: ADRMEM;
BEGIN
  {$INITCK+}
  NEW(p, 3); q := p;
  IF q = p THEN WRITELN('same ', UPPER(p^));
  grow(b.cells, 5); b.n := 1;
  WRITELN(top(b.cells), ' ', top(make(2)));
  q := NIL;
  IF q = NIL THEN WRITELN('nil');
  raw := UNSAFERAW(p);
  {$INITCK-} q := UNSAFESUPER(P, raw, 1, 2); {$INITCK+}
  WRITELN(UPPER(q^));
  DISPOSE(p); DISPOSE(b.cells)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok desc-ok 'same 3\n5 2\nnil\n2\n' extended

for kind in upper compare dispose element copy field formal result; do
  decl='p: P'; pre=''; body='WRITELN(UPPER(p^))'; what='local p'; needle='^'
  extra=''; line=8
  case "$kind" in
    compare) body="IF p = NIL THEN WRITELN('nil')"; needle='p = NIL' ;;
    dispose) body='DISPOSE(p)'; needle='p)' ;;
    # Selecting an element reads the descriptor at its `^` first.
    element) body='p^[1] := 1' ;;
    copy) decl='p, q: P'; pre='q := p;'; body='WRITELN(UPPER(q^))'; what='local q' ;;
    field) decl='b: RECORD n: INTEGER; cells: P END'; pre='b.n := 1;'
      body='WRITELN(UPPER(b.cells^))'; what='component b.cells' ;;
    formal) extra='PROCEDURE show(d: P); BEGIN {$INITCK+} WRITELN(UPPER(d^)) {$INITCK-} END;'
      pre='show(p);'; body="WRITELN('unreached')"; what='parameter d'; line=4 ;;
    result) extra='FUNCTION unset: P; BEGIN {$INITCK-} WRITELN(0) {$INITCK+} END {$INITCK-};'
      pre='p := unset;'; body="WRITELN('unreached')"; what='result of unset'; line=4; needle='END' ;;
  esac
  prefix='prefix\n'
  if [ "$kind" = result ]; then prefix='prefix\n0\n'; fi
  cat > "$work/desc-bad.pas" <<PAS
PROGRAM descbad;
TYPE Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
$extra
PROCEDURE probe;
VAR $decl;
BEGIN WRITELN('prefix'); $pre
  {\$INITCK+} $body; {\$INITCK-}
  WRITELN('after')
END;
BEGIN probe END.
PAS
  sed -i '1i { DIALECT: extended }' "$work/desc-bad.pas"
  line=$((line + 1))
  expect_fail desc-bad "$prefix" "runtime error: INITCK uninitialized $what at $(at desc-bad "$line" "$needle")"
done

# IR: NEW publishes the descriptor's state after its whole-value store; the
# descriptor guard precedes the descriptor load and UPPER's NIL check.
cat > "$work/desc-ir.pas" <<'PAS'
{ DIALECT: extended }
PROGRAM descir;
TYPE Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
PROCEDURE probe;
VAR p: P;
BEGIN NEW(p, 2); {$INITCK+} WRITELN(UPPER(p^)) {$INITCK-} END;
BEGIN probe END.
PAS
bin/pascal1981 -O0 -S "$work/desc-ir.pas" -o "$work/desc-ir.ll"
python3 - "$work/desc-ir.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
new = f.index('call ptr @pas_super_new(')
store = f.index('store { ptr, i64 } ', new)
publish = f.index('store i1 true, ptr %initck.p,', store)
ready = f.index('load i1, ptr %initck.p', publish)
fail = f.index('call void @pas_initck_error', ready)
load = f.index('load { ptr, i64 }, ptr %p', ready)
nil = f.index('call void @pas_upper_nil_error', load)
assert fail < load < nil
print('PASS: descriptor publication, guard before descriptor load and NIL check')
PY

# --- Allocation failure is transactional (initck_heap_publication.c). ---
# A failed data allocation or failed state allocation aborts before the
# destination or any state is published: destinations and the old
# referents' state are unchanged, and nothing new is registered. Ordinary
# NEW aborts on allocation failure like the SUPER ARRAY form, instead of
# publishing NIL.
cat > "$work/heap-fail.pas" <<'PAS'
{ DIALECT: extended }
PROGRAM heapfail(input, output);
TYPE R = RECORD v, w: INTEGER END;
     PR = ^R;
     Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
VAR slot: PR; cells: P; keep: ARRAY [1..46] OF PR; mode: INTEGER32; i: INTEGER;
PROCEDURE Arm(m: INTEGER32) [C]; EXTERN;
BEGIN
  READLN(mode);
  NEW(slot); slot^.v := 7; NEW(cells, 2); cells^[1] := 9;
  { Mode 5: 48 registrations, so the next one grows the registry table. }
  IF mode = 5 THEN FOR i := 1 TO 46 DO NEW(keep[i]);
  Arm(mode);
  IF (mode = 3) OR (mode = 4) THEN NEW(cells, 3) ELSE NEW(slot);
  WRITELN('UNEXPECTED: NEW returned')
END.
PAS
reasons=('NEW allocation failed' 'INITCK heap state allocation failed'
         'NEW SUPER ARRAY allocation failed' 'INITCK heap state allocation failed'
         'INITCK heap state allocation failed')
for opt in 0 2; do
  bin/pascal1981 --dialect extended -O"$opt" -S "$work/heap-fail.pas" -o "$work/heap-fail.ll"
  clang -O"$opt" "$work/heap-fail.ll" tests/initck_heap_publication.c runtime/build/libpascalrt.a -lm \
    -Wl,--wrap=malloc,--wrap=calloc,--wrap=abort -o "$work/heap-fail"
  for mode in 1 2 3 4 5; do
    status=0
    { printf '%s\n' "$mode" | "$work/heap-fail" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
    printf 'runtime error: %s\n' "${reasons[mode-1]}" > "$work/expected-err"
    printf 'PASS: nothing published or registered\n' > "$work/expected"
    if [ "$status" -ne 134 ] || ! cmp -s "$work/expected" "$work/actual" || ! cmp -s "$work/expected-err" "$work/err"; then
      echo "FAIL: heap failure mode $mode at O$opt (exit $status)" >&2; cat "$work/err" >&2; exit 1
    fi
  done
done
echo 'PASS: data and state allocation failures publish and register nothing'

# IR: the ordinary NEW failure branch precedes registration and publication.
python3 - "$work/heap-ir.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
alloc = f.index('call ptr @malloc(i64 4)')
check = re.search(r'%\S+ = icmp eq ptr %\S+, null\n\s+br i1 %\S+, label %new\.fail, label %new\.ok', f[alloc:])
assert check
ok = f.index('new.ok:', alloc)
assert f.index('call void @pas_initck_heap_new(', alloc) > ok
fail = f[f.index('new.fail:'):]
assert re.match(r'new\.fail:.*?\n\s+call void @pas_new_error\(\)\n\s+unreachable', fail, re.S)
print('PASS: NEW failure branch before registration and publication')
PY

# --- Heap SUPER ARRAY elements: per-element state of the NEW allocation. ---
# NEW(p, n) initializes the descriptor only; every leaf of every element
# starts unset, and each element is found within the allocation's state by
# the descriptor's data address and bounds.
cat > "$work/super-ok.pas" <<'PAS'
{ DIALECT: extended }
PROGRAM superok;
TYPE Cells = SUPER ARRAY [-1..*] OF INTEGER;
     P = ^Cells;
     R = RECORD a: CHAR; ok: BOOLEAN END;
     Rs = SUPER ARRAY [1..*] OF R;
     PR = ^Rs;
     Node = RECORD v: INTEGER END;
     PN = ^Node;
     Links = SUPER ARRAY [0..*] OF PN;
     PL = ^Links;
     V4 = VECTOR [4] OF INTEGER;
PROCEDURE swap(VAR x, y: INTEGER);
VAR t: INTEGER;
BEGIN t := x; x := y; y := t END;
PROCEDURE fill(d: P; v: INTEGER);
VAR i: INTEGER;
BEGIN FOR i := -1 TO RETYPE(INTEGER, UPPER(d^)) DO d^[i] := v + i END;
FUNCTION make(n: INTEGER): PR;
VAR t: PR;
BEGIN NEW(t, n); make := t END;
PROCEDURE probe(k: INTEGER);
VAR p, q: P; r: PR; l: PL; n: PN; i: INTEGER;
BEGIN
  {$INITCK+}
  NEW(p, 3); p^[-1] := -32768; p^[0] := 0;
  FOR i := 1 TO 3 DO p^[i] := i * k;
  q := p; swap(q^[1], q^[3]);
  WRITELN(p^[-1], ' ', p^[0], ' ', p^[1], ' ', q^[3]);
  fill(p, 10); WRITELN(p^[2]);
  r := make(2); r^[2].a := 'x'; r^[2].ok := FALSE;
  WITH r^[1] DO BEGIN a := 'y'; ok := TRUE END;
  WRITELN(r^[1].a, r^[2].a, ORD(r^[1].ok), ORD(r^[2].ok));
  NEW(l, 1); NEW(l^[0]); n := l^[0]; n^.v := 7; l^[1] := l^[0];
  n := l^[1]; WRITELN(n^.v);
  { VSTORE writes elements through a path INITCK does not model: the
    allocation is released and reads as initialized afterwards. }
  NEW(p, 2); {$INITCK-} VSTORE(p^, -1, VSPLAT(4, V4)); {$INITCK+} WRITELN(p^[2]);
  DISPOSE(p); DISPOSE(r); DISPOSE(n); DISPOSE(l)
  {$INITCK-}
END;
BEGIN probe(1); probe(2) END.
PAS
expect_ok super-ok '-32768 0 3 1\n12\nyx10\n7\n4\n-32768 0 6 2\n12\nyx10\n7\n4\n' extended

for kind in fresh neighbor field renew alias var with taint; do
  decl='p: P'; pre='NEW(p, 2)'; body='WRITELN(p^[1])'; what='component p^[1]'; needle='p^[1]'
  extra=''; line=11
  case "$kind" in
    neighbor) pre='NEW(p, 2); p^[1] := 1'; body='WRITELN(p^[2])'; what='component p^[2]'; needle='p^[2]' ;;
    field) decl='r: PR'; pre="NEW(r, 2); r^[2].a := 'x'"; body='WRITELN(r^[2].ok)'
      what='component r^[2].ok'; needle='r^[2].ok' ;;
    renew) pre='NEW(p, 2); p^[1] := 1; NEW(p, 2)' ;;
    alias) decl='p, q: P'; pre='NEW(p, 2); q := p; q^[1] := 1'; body='WRITELN(q^[1], p^[2])'
      what='component p^[2]'; needle='p^[2]' ;;
    var) extra='PROCEDURE show(VAR x: INTEGER); BEGIN {$INITCK+} WRITELN(x) {$INITCK-} END;'
      body='show(p^[2])'; what='parameter x'; line=8; needle='x)' ;;
    with) decl='r: PR'; pre="NEW(r, 1); r^[1].a := 'x'"; body='WITH r^[1] DO WRITELN(a, ok)'
      what='field ok'; needle='ok)' ;;
    taint) decl='p: P; x: INTEGER'; pre='NEW(p, 2); x := p^[2] + 0'; body='WRITELN(x)'
      what='local x'; needle='x)' ;;
  esac
  cat > "$work/super-bad.pas" <<PAS
{ DIALECT: extended }
PROGRAM superbad;
TYPE Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
     R = RECORD a: CHAR; ok: BOOLEAN END;
     Rs = SUPER ARRAY [1..*] OF R;
     PR = ^Rs;
$extra
VAR g: INTEGER;
PROCEDURE probe; VAR $decl; BEGIN $pre; WRITELN('prefix');
  {\$INITCK+} $body; {\$INITCK-}
  WRITELN('after')
END;
BEGIN probe END.
PAS
  expect_fail super-bad 'prefix\n' "runtime error: INITCK uninitialized $what at $(at super-bad "$line" "$needle")"
done

# Exported elements are released (UNSAFERAW, here written by C), and
# imported memory is untracked: neither is ever a false positive.
cat > "$work/super-raw.pas" <<'PAS'
{ DIALECT: extended }
PROGRAM superraw;
TYPE Chars = SUPER ARRAY [1..*] OF CHAR;
     P = ^Chars;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE probe;
VAR p, q: P; raw: ADRMEM;
BEGIN
  NEW(p, 2); fillc(UNSAFERAW(p), 2, 'z');
  {$INITCK+} WRITELN(p^[1], p^[2]); {$INITCK-}
  raw := malloc(2); fillc(raw, 2, 'm'); q := UNSAFESUPER(P, raw, 1, 2);
  {$INITCK+} WRITELN(q^[1], q^[2]) {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok super-raw 'zz\nmm\n' extended

# IR: NEW records count * leaves element states after pas_super_new and
# before the descriptor is published; an element read finds its state after
# the bounds check and branches on it before the native element load.
cat > "$work/super-ir.pas" <<'PAS'
{ DIALECT: extended }
PROGRAM superir;
TYPE R = RECORD a, b: INTEGER END;
     Rs = SUPER ARRAY [1..*] OF R;
     P = ^Rs;
PROCEDURE probe(i: INTEGER);
VAR p: P;
BEGIN NEW(p, i + 3); p^[1].a := 1; {$INITCK+} WRITELN(p^[i].b) {$INITCK-} END;
BEGIN probe(1) END.
PAS
bin/pascal1981 --dialect extended -O0 -S "$work/super-ir.pas" -o "$work/super-ir.ll"
python3 - "$work/super-ir.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
new = f.index('call ptr @pas_super_new(')
leaves = f.index('%initck.leaves', new)
assert re.search(r'%initck\.leaves\d* = mul i64 %\S+, 2\n', f[new:]), 'two leaves per element'
reg = f.index('call void @pas_initck_heap_new(ptr ', leaves)
store = f.index('store { ptr, i64 } ', reg)
publish = f.index('store i1 true, ptr %initck.p,', store)
read = f.rindex('call ptr @pas_initck_heap_part_at(ptr ')
assert re.search(r'call ptr @pas_initck_heap_part_at\(ptr %\S+, i64 %\S+, i64 %\S+, i64 2, ptr %initck\.untracked\d*\)', f[read:])
bounds = f.rindex('call void @pas_array_index_error', 0, read)
guard = f.index('call void @pas_initck_fail(', read)
load = f.index('load i16, ptr ', read)
assert publish < bounds < read < guard < load
print('PASS: SUPER element registration before publication; per-element lookup after bounds, before load')
PY

# --- DISPOSE retires a referent's state; a reused address starts afresh. ---
# A NEW after DISPOSE is a fresh, wholly unset referent, whether or not it
# reuses the address.
cat > "$work/renew-bad.pas" <<'PAS'
PROGRAM renewbad;
TYPE R = RECORD v, w: INTEGER END;
     PR = ^R;
PROCEDURE probe;
VAR p: PR;
BEGIN
  NEW(p); p^.v := 1; p^.w := 2; DISPOSE(p); NEW(p); WRITELN('prefix');
  {$INITCK+} WRITELN(p^.w) {$INITCK-}
END;
BEGIN probe END.
PAS
expect_fail renew-bad 'prefix\n' "runtime error: INITCK uninitialized component p^.w at $(at renew-bad 8 'p^.w')"

# Memory from C that reuses a disposed address must not inherit the old
# referent's state. The program reports whether the address was reused
# (glibc reuses it); then, as a mutation check, deleting the retirement
# from the IR must turn this correct program into a false positive.
cat > "$work/reuse.pas" <<'PAS'
PROGRAM reuse;
TYPE R = RECORD c1, c2: CHAR END;
     PR = ^R;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE probe;
VAR p, q, old: PR; a: ADRMEM;
BEGIN
  NEW(p); p^.c1 := 'a'; old := p; DISPOSE(p);
  a := malloc(2); fillc(a, 2, 'm'); q := a;
  IF q = old THEN WRITELN('reused') ELSE WRITELN('fresh');
  {$INITCK+} WRITELN(q^.c1, q^.c2) {$INITCK-}
END;
BEGIN probe END.
PAS
for opt in 0 2; do
  bin/pascal1981 --dialect extended -O"$opt" -S "$work/reuse.pas" -o "$work/reuse.ll"
  clang -O"$opt" "$work/reuse.ll" runtime/build/libpascalrt.a -lm -o "$work/reuse"
  "$work/reuse" > "$work/actual" 2> "$work/err"
  test ! -s "$work/err"
  reused=$(head -1 "$work/actual")
  printf '%s\nmm\n' "$reused" > "$work/expected"
  diff -u "$work/expected" "$work/actual"
  if [ "$reused" = reused ]; then
    grep -c 'call void @pas_initck_heap_dispose' "$work/reuse.ll" | grep -qx 1
    sed '/call void @pas_initck_heap_dispose/d' "$work/reuse.ll" > "$work/mutant.ll"
    clang -O"$opt" "$work/mutant.ll" runtime/build/libpascalrt.a -lm -o "$work/mutant"
    status=0
    { "$work/mutant" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
    test "$status" -ne 0
    grep -q 'INITCK uninitialized component q^.c2' "$work/err"
  else
    echo "NOTE: the C allocation did not reuse the disposed address at O$opt; mutation check skipped"
  fi
done

# IR: DISPOSE reads its pointer (guard first), then retires the state, then
# frees; a descriptor retires its elements' state by its data address.
cat > "$work/dispose-ir.pas" <<'PAS'
{ DIALECT: extended }
PROGRAM disposeir;
TYPE R = RECORD v: INTEGER END;
     PR = ^R;
     Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
PROCEDURE probe;
VAR p: PR; s: P;
BEGIN NEW(p); NEW(s, 2); {$INITCK+} DISPOSE(p); DISPOSE(s) {$INITCK-} END;
BEGIN probe END.
PAS
bin/pascal1981 --dialect extended -O0 -S "$work/dispose-ir.pas" -o "$work/dispose-ir.ll"
python3 - "$work/dispose-ir.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
f = re.search(r'define void @probe\(.*?\n\}', ir, re.S).group()
at = 0
for name, ty in (('p', 'ptr'), ('s', '{ ptr, i64 }')):
    ready = f.index('load i1, ptr %initck.' + name, at)
    fail = f.index('call void @pas_initck_error', ready)
    load = f.index('load %s, ptr %%%s' % (ty, name), ready)
    retire = f.index('call void @pas_initck_heap_dispose(ptr ', load)
    free = f.index('call void @free(ptr ', retire)
    assert fail < load < retire < free
    arg = re.match(r'call void @pas_initck_heap_dispose\(ptr (%\S+)\)', f[retire:]).group(1)
    assert re.match(r'call void @free\(ptr ' + re.escape(arg) + r'\)', f[free:])
    at = free
print('PASS: DISPOSE guard, retirement before free')
PY

# The registry itself: parts stay within an allocation, mismatches and
# releases read as initialized scratch, reuse replaces stale state.
clang -Wall -Wextra tests/initck_heap_runtime.c runtime/build/libpascalrt.a -o "$work/heap-runtime"
"$work/heap-runtime"

# --- Coverage: nested heap storage, aliases and recursion. ---
# Pointers to pointers, heap records holding descriptors and arrays of
# pointers, a recursive tree, whole-referent VAR/CONST bindings and value
# actuals, and heap variant records (the logical-field model).
cat > "$work/nest-ok.pas" <<'PAS'
{ DIALECT: extended }
PROGRAM nestok;
TYPE Tree = ^Node;
     Node = RECORD key: INTEGER; left, right: Tree END;
     PT = ^Tree;
     Cells = SUPER ARRAY [1..*] OF CHAR;
     PC = ^Cells;
     Holder = RECORD n: INTEGER; cells: PC; kids: ARRAY [1..2] OF Tree END;
     PH = ^Holder;
     Pair = RECORD a, b: INTEGER END;
     PP = ^Pair;
     V = RECORD CASE k: BOOLEAN OF TRUE: (i: INTEGER); FALSE: (c: CHAR) END;
     PV = ^V;
FUNCTION insert(t: Tree; k: INTEGER): Tree;
BEGIN
  IF t = NIL THEN BEGIN NEW(t); t^.key := k; t^.left := NIL; t^.right := NIL END
  ELSE IF k < t^.key THEN t^.left := insert(t^.left, k)
  ELSE t^.right := insert(t^.right, k);
  insert := t
END;
FUNCTION sum(t: Tree): INTEGER;
BEGIN IF t = NIL THEN sum := 0 ELSE sum := t^.key + sum(t^.left) + sum(t^.right) END;
PROCEDURE clear(VAR p: Pair);
BEGIN p.a := 0; p.b := -32768 END;
FUNCTION total(CONST p: Pair): INTEGER;
BEGIN total := p.a + p.b END;
FUNCTION copied(p: Pair): INTEGER;
BEGIN copied := p.b END;
PROCEDURE probe;
VAR t: Tree; pt: PT; h: PH; p: PP; v: PV; i: INTEGER;
BEGIN
  {$INITCK+}
  t := NIL;
  FOR i := 1 TO 5 DO t := insert(t, (i * 3) MOD 7);
  WRITELN(sum(t));
  NEW(pt); pt^ := t; NEW(pt^^.left^.left); pt^^.left^.left^.key := 9;
  WRITELN(pt^^.key, ' ', pt^^.left^.left^.key);
  NEW(h); h^.n := 2; NEW(h^.cells, 2); h^.cells^[1] := 'o'; h^.cells^[2] := 'k';
  h^.kids[1] := t; h^.kids[2] := NIL;
  WRITELN(h^.cells^[1], h^.cells^[2], ' ', UPPER(h^.cells^), ' ', h^.kids[1]^.key);
  NEW(p); clear(p^); WRITELN(total(p^), ' ', copied(p^));
  NEW(v); v^.k := FALSE; v^.c := 'z'; WRITELN(v^.c);
  v^.i := 5; WRITELN(v^.i);
  { A nested WITH cannot tell which target binds a name: its outer heap
    target is released (an enabled read inside is a boundary), and later
    checked reads of the referent never fail. }
  {$INITCK-} WITH h^ DO WITH kids[1]^ DO key := n; {$INITCK+}
  WRITELN(h^.kids[1]^.key)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok nest-ok '17\n3 9\nok 2 3\n-32768 -32768\nz\n5\n2\n' extended

for kind in ptrptr desc descelem deep var const value variant tag; do
  decl='t: Tree'; pre='NEW(t)'; extra=''; line=12
  case "$kind" in
    # A pointer stored in a referent is read at its own `^`.
    ptrptr) decl='pt: PT'; pre='NEW(pt)'; body='pt^^.key := 1'; what='component pt^'; needle='^.key' ;;
    desc) decl='h: PH'; pre='NEW(h)'; body='WRITELN(UPPER(h^.cells^))'; what='component h^.cells'; needle='^)' ;;
    descelem) decl='h: PH'; pre="NEW(h); NEW(h^.cells, 2); h^.cells^[1] := 'o'"
      body='WRITELN(h^.cells^[2])'; what='component h^.cells^[2]'; needle='h^.cells^[2]' ;;
    deep) pre='NEW(t); NEW(t^.left); t^.left^.key := 1'; body='WRITELN(t^.left^.right = NIL)'
      what='component t^.left^.right'; needle='t^.left^.right' ;;
    # Whole-referent bindings share the referent's leaves.
    var) decl='p: PP'; pre='NEW(p); half(p^)'; body='WRITELN(p^.b)'; what='component p^.b'; needle='p^.b' ;;
    const) decl='p: PP'; pre='NEW(p); p^.a := 1'; body='WRITELN(total(p^))'
      what='component p.b'; needle='p.b'; line=8 ;;
    value) decl='p: PP'; pre='NEW(p); p^.a := 1'; body='WRITELN(copied(p^))'; what='part of p^'; needle='p^)' ;;
    # Heap variant records: alternatives never initialize each other, and
    # the tag is an ordinary field.
    variant) decl='v: PV'; pre="NEW(v); v^.k := FALSE; v^.c := 'z'"; body='WRITELN(v^.i)'
      what='component v^.i'; needle='v^.i' ;;
    tag) decl='v: PV'; pre="NEW(v); v^.c := 'z'"; body='WRITELN(ORD(v^.k))'; what='component v^.k'; needle='v^.k' ;;
  esac
  cat > "$work/nest-bad.pas" <<PAS
{ DIALECT: extended }
PROGRAM nestbad;
TYPE Tree = ^Node; Node = RECORD key: INTEGER; left, right: Tree END;
     PT = ^Tree; Cells = SUPER ARRAY [1..*] OF CHAR; PC = ^Cells;
     Holder = RECORD n: INTEGER; cells: PC END; PH = ^Holder;
     Pair = RECORD a, b: INTEGER END; PP = ^Pair;
     V = RECORD CASE k: BOOLEAN OF TRUE: (i: INTEGER); FALSE: (c: CHAR) END; PV = ^V;
FUNCTION total(CONST p: Pair): INTEGER; BEGIN {\$INITCK+} total := p.a + p.b {\$INITCK-} END;
FUNCTION copied(p: Pair): INTEGER; BEGIN copied := p.a END;
PROCEDURE half(VAR p: Pair); BEGIN p.a := 1 END;
PROCEDURE probe; VAR $decl; BEGIN $pre; WRITELN('prefix');
  {\$INITCK+} $body; {\$INITCK-}
  WRITELN('after')
END;
BEGIN probe END.
PAS
  expect_fail nest-bad 'prefix\n' "runtime error: INITCK uninitialized $what at $(at nest-bad "$line" "$needle")"
done

# --- Boundaries: pointer storage without state, untracked heap storage. ---
cat > "$work/global-ptr.pas" <<'PAS'
PROGRAM globalptr;
TYPE PR = ^INTEGER;
VAR g: PR;
PROCEDURE probe;
BEGIN NEW(g); {$INITCK+} g^ := 1 {$INITCK-} END;
BEGIN probe END.
PAS
expect_boundary global-ptr 'global or captured storage'
# An address-taken pointer local stays tracked (ADR releases it): see
# initck_external.sh.
# A referent outside the tracked slice (here a record with a REAL field).
cat > "$work/heap-real.pas" <<'PAS'
PROGRAM heapreal;
TYPE R = RECORD v: INTEGER; x: REAL END;
     PR = ^R;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); p^.v := 1; {$INITCK+} WRITELN(p^.v) {$INITCK-} END;
BEGIN probe END.
PAS
expect_boundary heap-real 'heap storage'
# A WITH whose body hands a field to an unmodeled effect releases the
# referent and binds untracked fields.
cat > "$work/heap-with.pas" <<'PAS'
PROGRAM heapwith;
TYPE R = RECORD c1, c2: CHAR END;
     PR = ^R;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); WITH p^ DO BEGIN fillc(ADR c1, 2, 'z'); {$INITCK+} WRITELN(c2) {$INITCK-} END END;
BEGIN probe END.
PAS
expect_boundary heap-with 'untracked WITH target'
# SUPER ARRAY elements outside the tracked slice (REAL here).
cat > "$work/super-real.pas" <<'PAS'
{ DIALECT: extended }
PROGRAM superreal;
TYPE Reals = SUPER ARRAY [1..*] OF REAL;
     P = ^Reals;
PROCEDURE probe;
VAR p: P;
BEGIN NEW(p, 2); p^[1] := 1.0; {$INITCK+} WRITELN(p^[1]:3:1) {$INITCK-} END;
BEGIN probe END.
PAS
expect_boundary super-real 'heap storage'
# (A whole heap aggregate cannot reach READ/WRITE here: only TEXT files and
# scalar/string items are supported, and the typechecker rejects the rest.)

echo 'PASS: INITCK pointers and heap storage'
