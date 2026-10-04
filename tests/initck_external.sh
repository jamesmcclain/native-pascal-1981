#!/usr/bin/env bash
# INITCK at external boundaries: C code that reads or writes Pascal storage.
# Executed programs link generated IR with a C helper; uninitialized reads
# are never executed unchecked as if their output meant anything.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ulimit -c 0

# link NAME OPT [EXTRA...]: compile $work/NAME.pas (extended dialect) to IR and
# link it with $work/cside.c and the runtime.
link() {
  local name=$1 opt=$2
  shift 2
  bin/pascal1981 --dialect extended -O"$opt" -S "$work/$name.pas" -o "$work/$name.ll" 2> "$work/err"
  test ! -s "$work/err"
  clang -O"$opt" "$work/$name.ll" "$work/cside.c" "$@" runtime/build/libpascalrt.a -lm -o "$work/$name"
}
# expect_ok NAME EXPECTED / expect_fail NAME PREFIX ERROR, at O0 and O2.
expect_ok() {
  local name=$1
  printf '%b' "$2" > "$work/$name.expected"
  for opt in 0 2; do
    link "$name" "$opt"
    "$work/$name" > "$work/actual" 2> "$work/err"
    diff -u "$work/$name.expected" "$work/actual"
    test ! -s "$work/err"
  done
}
expect_fail() {
  local name=$1
  printf '%b' "$2" > "$work/$name.expected"
  printf '%s\n' "$3" > "$work/$name.expected-err"
  for opt in 0 2; do
    link "$name" "$opt"
    status=0
    { "$work/$name" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
    test "$status" -ne 0
    diff -u "$work/$name.expected" "$work/actual"
    diff -u "$work/$name.expected-err" "$work/err"
  done
}
# col FILE LINE NEEDLE: 1-based column of NEEDLE's last occurrence on LINE.
col() { echo $(( $(sed -n "$2p" "$1" | grep -bo "$3" | tail -1 | cut -d: -f1) + 1 )); }

cat > "$work/cside.c" <<'C'
#include <stdint.h>
/* [C] routines: VAR/CONST formals arrive as plain pointers. */
void cset(int16_t *v) { *v = 7; }
void cfill(char *v) { v[0] = 'o'; v[1] = 'k'; }
void cpeek(const int16_t *v) { (void) v; }
/* Plain (non-[C]) EXTERN routines implemented in C: they ignore the INITCK
 * side channel. relay calls the Pascal cb back while its own caller's slots
 * are still published; cval calls a Pascal function that publishes an unset
 * result before returning its own value. */
void pset(int16_t *v) { *v = 9; }
void pwrite(int16_t *p) { *p = 11; }
void cb(int16_t *n) __attribute__((weak)); /* absent from some programs */
void relay(int16_t *v) { int16_t mine = 5; cb(&mine); *v = mine; }
int16_t unsetres(void) __attribute__((weak));
int16_t cval(void) { (void) unsetres(); return 42; }
/* Raw writes: through an ADRMEM, and through a host SUPER ARRAY descriptor
 * {data, upper} (lower bound 1) passed by value or by VAR to plain EXTERNs. */
void poke(int16_t *a, int16_t v) { *a = v; }
void *cmem(void) { static int16_t cell; return &cell; }
typedef struct { int16_t *data; int64_t upper; } Desc;
void dfill(Desc d) { for (int64_t i = 0; i < d.upper; i++) d.data[i] = (int16_t) (10 * (i + 1)); }
void dfillv(Desc *d) { d->data[0] = 77; }
/* Review regressions: writers whose first argument is also read by a later
 * actual, a function that ignores its argument, and a second raw cell. */
void cpair(int16_t *v, int16_t b) { *v = b; }
void cptr(int16_t *p, int16_t b) { *p = b; }
void cadr(void *a, int16_t b) { *(int16_t *) a = b; }
int16_t cfive(int16_t n) { (void) n; return 5; }
void *cmem2(void) { static int16_t cell; return &cell; }
C

# --- C calls that write Pascal storage. ---
# A [C] VAR or CONST binding hands C the address of exactly the bound storage
# (a whole local, a component, a whole aggregate): that extent, and nothing
# else, becomes initialized at the call, after every actual is evaluated;
# binding is not a read. A plain EXTERN that turns out to be C (no handshake
# acknowledgement) releases the storage bound to its VAR/CONST formals after
# the call, and its result state is initialized. A Pascal routine C calls back while such a call's slots are
# published sees another routine's tag and ignores them.
cat > "$work/cwrite.pas" <<'PAS'
PROGRAM cwrite;
TYPE A2 = ARRAY [1..2] OF CHAR; PI = ^INTEGER;
PROCEDURE cset(VAR v: INTEGER) [C]; EXTERN;
PROCEDURE cfill(VAR v: A2) [C]; EXTERN;
PROCEDURE cpeek(CONST v: INTEGER) [C]; EXTERN;
PROCEDURE pset(VAR v: INTEGER); EXTERN;
PROCEDURE pwrite(p: PI); EXTERN;
PROCEDURE relay(VAR v: INTEGER); EXTERN;
FUNCTION cval: INTEGER; EXTERN;
PROCEDURE cb(VAR n: INTEGER); BEGIN {$INITCK+} n := n + 1 {$INITCK-} END;
FUNCTION unsetres: INTEGER; BEGIN END;
PROCEDURE probe;
VAR x, y, z, w, k: INTEGER; a: A2; m: ARRAY [1..2] OF INTEGER; q: PI;
BEGIN
  {$INITCK+}
  cset(x); WRITELN(x);
  cfill(a); WRITELN(a[1], a[2]);
  m[1] := 1; cset(m[2]); WRITELN(m[1] + m[2]);
  k := 3; cpeek(k); WRITELN(k);
  pset(y); WRITELN(y);
  relay(z); WRITELN(z);
  w := cval; WRITELN(w);
  NEW(q); pwrite(q); WRITELN(q^)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok cwrite '7\nok\n8\n3\n9\n6\n42\n11\n'
# The released extent is exact: a sibling component and an unrelated local
# stay unset.
for kind in sibling other; do
  case "$kind" in
    sibling) body='cset(m[2]); WRITELN(m[2]); WRITELN(m[1])'; err='component m[1]'; needle='m\[1\]' ;;
    other) body='cset(x); WRITELN(x); WRITELN(y)'; err='local y'; needle='y)' ;;
  esac
  printf 'PROGRAM cbad;\nPROCEDURE cset(VAR v: INTEGER) [C]; EXTERN;\nPROCEDURE probe;\nVAR x, y: INTEGER; m: ARRAY [1..2] OF INTEGER;\nBEGIN {$INITCK+} %s {$INITCK-} END;\nBEGIN probe END.\n' "$body" > "$work/cbad.pas"
  expect_fail cbad '7\n' "runtime error: INITCK uninitialized $err at line 5 column $(col "$work/cbad.pas" 5 "$needle")"
done

# Each mechanism is load-bearing: without the post-call release the
# C-written y is a false positive; with cb trusting the tag unconditionally
# it binds relay's caller's unset slot; without the acknowledgement test the
# unset result cval's callback published becomes w's state; without the
# referent release C's write through pwrite's pointer is a false positive.
for mutation in release tag ack heap; do
  bin/pascal1981 --dialect extended -O0 -S "$work/cwrite.pas" -o "$work/mut.ll"
  python3 - "$work/mut.ll" "$mutation" <<'PY'
import re, sys
path, mutation = sys.argv[1:]
ir = open(path).read()
if mutation == 'release':
    ir, n = re.subn(r'\n *call void @pas_initck_release_unacked\([^\n]*', '', ir)
elif mutation == 'heap':
    ir, n = re.subn(r'\n *call void @pas_initck_heap_release\([^\n]*', '', ir)
elif mutation == 'tag':
    ir, n = re.subn(r'(%initck\.mine[0-9]* = )icmp eq ptr %initck\.tag[0-9]*, @cb\b', r'\1icmp ne ptr null, @cb', ir)
else:
    ir, n = re.subn(r'xor i1 %initck\.acked[0-9]*, true', 'xor i1 true, true', ir)
assert n >= 1, mutation
open(path, 'w').write(ir)
PY
  clang -O0 "$work/mut.ll" "$work/cside.c" runtime/build/libpascalrt.a -lm -o "$work/mut"
  status=0
  { "$work/mut" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
  test "$status" -ne 0
  case "$mutation" in
    release) grep -q '^runtime error: INITCK uninitialized local y ' "$work/err" ;;
    tag) grep -q '^runtime error: INITCK uninitialized parameter n ' "$work/err" ;;
    ack) grep -q '^runtime error: INITCK uninitialized local w ' "$work/err" ;;
    heap) grep -q '^runtime error: INITCK uninitialized component q^ ' "$work/err" ;;
  esac
done

# IR shape. A plain EXTERN call that publishes gets the callee tag and a
# flag, then clears the tag, reads the flag and releases its VAR binding; a
# call to a routine defined here gets the tag and a NULL flag, and no release.
# A [C] VAR binding is filled before the call. The callee compares the tag
# before its first slot load.
bin/pascal1981 --dialect extended -O0 -S "$work/cwrite.pas" -o "$work/cwrite.ll"
python3 - "$work/cwrite.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
def body(name):
    b = ir[ir.index(f'define {name}'):]
    return b[:b.index('\n}')]
probe = body('void @probe(')
i_tag = probe.index('store ptr @pset, ptr @pas_initck_callee')
i_ack = probe.index('ptr @pas_initck_ack', i_tag)
i_call = probe.index('call void @pset(', i_ack)
i_acked = probe.index('load i1, ptr %initck.ack', i_call)
i_clear = probe.index('store ptr null, ptr @pas_initck_callee', i_call)
i_rel = probe.index('call void @pas_initck_release_unacked(', i_acked)
assert i_clear < i_rel
cset = probe.index('call void @cset(')
assert re.search(r'store i1 true, ptr %initck\.x,[^\n]*\n *call void @cset\(', probe)
assert 'call void @pas_initck_fill(ptr %initck.a' in probe[:probe.index('call void @cfill(')]
assert 'store ptr @cset' not in probe  # [C] routines take no part
cb = body('void @cb(')
mine = re.search(r'%initck\.mine[0-9]* = icmp eq ptr %initck\.tag[0-9]*, @cb', cb)
assert mine and mine.start() < cb.index('@pas_initck_args')
assert re.search(r'%initck\.argok[0-9]* = select i1 %initck\.mine', cb)
PY

# A plain EXTERN implemented in instrumented Pascal (a MODULE compiled
# separately) acknowledges the handshake, so nothing is released: its writes
# through VAR publish exactly what they wrote and its unset result stays
# unset. Unacknowledged release is for C only, not a blanket assumption.
cat > "$work/extmod.module" <<'PAS'
MODULE extmod;
TYPE PI = ^INTEGER;
PROCEDURE mptr(p: PI; w: BOOLEAN);
BEGIN IF w THEN p^ := 6 END;
PROCEDURE mset(VAR v: INTEGER; w: BOOLEAN);
BEGIN IF w THEN v := 4 END;
FUNCTION mres(w: BOOLEAN): INTEGER;
BEGIN IF w THEN mres := 5 END;
END.
PAS
# The pointer case: mptr's write through a typed pointer value it received
# is a published heap write, so an instrumented callee releases nothing.
cat > "$work/modhost.tmpl" <<'PAS'
PROGRAM modhost; TYPE PI = ^INTEGER;
PROCEDURE mset(VAR v: INTEGER; w: BOOLEAN); EXTERN;
FUNCTION mres(w: BOOLEAN): INTEGER; EXTERN;
PROCEDURE mptr(p: PI; w: BOOLEAN); EXTERN;
PROCEDURE probe(a, b, c: BOOLEAN);
VAR x, y: INTEGER; q: PI;
BEGIN
  mset(x, a); {$INITCK+} WRITELN(x); {$INITCK-}
  y := mres(b); {$INITCK+} WRITELN(y); {$INITCK-}
  NEW(q); mptr(q, c); {$INITCK+} WRITELN(q^) {$INITCK-}
END;
BEGIN @CALLS@ END.
PAS
modcheck() { # NAME CALLS STDOUT [ERROR-WITHOUT-COLUMN LINE NEEDLE]
  sed "s/@CALLS@/$2/" "$work/modhost.tmpl" > "$work/$1.pas"
  printf '%b' "$3" > "$work/expected"
  : > "$work/expected-err"
  if [ $# -gt 3 ]; then
    printf '%s at line %s column %s\n' "$4" "$5" "$(col "$work/$1.pas" "$5" "$6")" > "$work/expected-err"
  fi
  for opt in 0 2; do
    bin/pascal1981 --dialect extended -O"$opt" "$work/$1.pas" "$work/extmod.module" -o "$work/$1" 2> "$work/err"
    test ! -s "$work/err"
    status=0
    { "$work/$1" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
    if [ $# -gt 3 ]; then test "$status" -ne 0; else test "$status" -eq 0; fi
    diff -u "$work/expected" "$work/actual"
    diff -u "$work/expected-err" "$work/err"
  done
}
ok='probe(TRUE, TRUE, TRUE)'
modcheck modok "$ok" '4\n5\n6\n'
modcheck modvar "$ok; probe(FALSE, TRUE, TRUE)" '4\n5\n6\n' \
  'runtime error: INITCK uninitialized local x' 8 'x)'
modcheck modres "$ok; probe(TRUE, FALSE, TRUE)" '4\n5\n6\n4\n' \
  'runtime error: INITCK uninitialized local y' 9 'y)'
modcheck modptr "$ok; probe(TRUE, TRUE, FALSE)" '4\n5\n6\n4\n5\n' \
  'runtime error: INITCK uninitialized component q^' 10 'q^)'
# --- Raw addresses, unsafe conversions and imported descriptors. ---
# ADR of a routine symbol (a local or formal, scalar or aggregate) releases
# every leaf of it where the ADR is evaluated (as a call's actual: at the
# call, after its other actuals): raw writes through the address
# (fillc, a typed pointer converted from it, C) are not modeled, and the slot
# stays tracked before that point. A control variable whose address the
# routine takes is not unset by a natural FOR exit. A descriptor a C plain
# EXTERN receives releases the elements it locates.
cat > "$work/raw.pas" <<'PAS'
PROGRAM raw;
TYPE PI = ^INTEGER; A3 = ARRAY [1..3] OF BOOLEAN;
     Cells = SUPER ARRAY [1..*] OF INTEGER; PC = ^Cells;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE poke(a: ADRMEM; v: INTEGER); EXTERN;
FUNCTION cmem: ADRMEM [C]; EXTERN;
PROCEDURE dfill(d: PC); EXTERN;
PROCEDURE dfillv(VAR d: PC); EXTERN;
PROCEDURE viaformal(VAR v: INTEGER);
VAR a: ADRMEM;
BEGIN a := ADR v; poke(a, 12); {$INITCK+} WRITELN(v) {$INITCK-} END;
PROCEDURE probe;
VAR flags: A3; x, y, i, f: INTEGER; q, p: PI; a: ADRMEM; d, g: PC;
BEGIN
  {$INITCK+}
  fillc(ADR flags, 3, CHR(1)); WRITELN(flags[1], ' ', flags[3]);
  q := ADR x; q^ := 99; WRITELN(x);
  viaformal(y); WRITELN(y);
  a := ADR i; FOR i := 1 TO 3 DO f := i; poke(a, 5); WRITELN(i + f);
  NEW(p); a := ADR p; p^ := 1; WRITELN(p^);
  NEW(d, 3); dfill(d); WRITELN(d^[1] + d^[2] + d^[3]);
  NEW(g, 2); dfillv(g); WRITELN(g^[1]);
  a := cmem; poke(a, 3); WRITELN(a = NIL)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok raw 'TRUE TRUE\n99\n12\n12\n8\n1\n60\n77\nFALSE\n'
# Release happens where ADR is evaluated, for that symbol only: a read before
# it, an untaken ADR and another local all still fail. A raw address is a
# value leaf: an unset one fails when read, and an unchecked unset one
# reaches a Pascal callee unset; a [C] function's ADRMEM result is an
# initialized (untracked) value (raw.pas).
for kind in before untaken other adrmem transport; do
  what='local x'; needle='x)'
  case "$kind" in
    before) body='WRITELN(x); a := ADR x' ;;
    untaken) body='IF n > 0 THEN a := ADR x; WRITELN(x)' ;;
    other) body='a := ADR y; WRITELN(x)' ;;
    adrmem) body='IF n > 0 THEN a := ADR x; poke(a, 2)'; what='local a'; needle='a, 2' ;;
    transport) body='{$INITCK-} pass(a) {$INITCK+}'; what='parameter b'; needle='b, 1' ;;
  esac
  printf 'PROGRAM rawbad;\nPROCEDURE poke(a: ADRMEM; v: INTEGER); EXTERN; FUNCTION cmem: ADRMEM [C]; EXTERN;\nPROCEDURE pass(b: ADRMEM); BEGIN {$INITCK+} poke(b, 1) {$INITCK-} END;\nPROCEDURE probe(n: INTEGER);\nVAR x, y: INTEGER; a: ADRMEM;\nBEGIN {$INITCK+} %s {$INITCK-} END;\nBEGIN WRITELN(%s); probe(0) END.\n' "$body" "'prefix'" > "$work/rawbad.pas"
  line=6; [ "$kind" = transport ] && line=3
  expect_fail rawbad 'prefix\n' "runtime error: INITCK uninitialized $what at line $line column $(col "$work/rawbad.pas" $line "$needle")"
done
# Load-bearing: without the ADR release the fillc-written array fails;
# without the descriptor release C's elements fail.
for mutation in adr desc; do
  bin/pascal1981 --dialect extended -O0 -S "$work/raw.pas" -o "$work/mut.ll"
  case "$mutation" in
    adr) pattern='call void @pas_initck_fill(ptr %initck.flags'; err='component flags\[1\]' ;;
    desc) pattern='call void @pas_initck_heap_release(ptr %'; err='component d^\[1\]' ;;
  esac
  grep -qF "$pattern" "$work/mut.ll"
  grep -vF "$pattern" "$work/mut.ll" > "$work/mutant.ll"
  clang -O0 "$work/mutant.ll" "$work/cside.c" runtime/build/libpascalrt.a -lm -o "$work/mut"
  status=0
  { "$work/mut" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
  test "$status" -ne 0
  grep -q "^runtime error: INITCK uninitialized $err " "$work/err"
done
# The FOR exception is exactly the address-taken control variable: a twin
# without the ADR still unsets i on the natural-exit edge.
probe_ir() { python3 -c 'import sys; ir = open(sys.argv[1]).read(); b = ir[ir.index("define void @probe("):]; print(b[:b.index("\n}")])' "$1"; }
probe_ir "$work/mut.ll" > "$work/with-adr.ll"
! grep -q '^for_done' "$work/with-adr.ll"
sed 's/a := ADR i; FOR/a := ADR f; FOR/' "$work/raw.pas" > "$work/noadr.pas"
bin/pascal1981 --dialect extended -O0 -S "$work/noadr.pas" -o "$work/noadr.ll"
probe_ir "$work/noadr.ll" | grep -A1 '^for_done' | grep -q 'store i1 false, ptr %initck\.i,'
# --- Files and aggregate I/O. ---
# Naming a file (RESET, REWRITE, GET, PUT, CLOSE, ASSIGN, EOF, EOLN, the
# file argument of READ/WRITE) consumes control state its initialization
# set, not Pascal data. A buffer F^ whose component type is tracked has
# per-leaf state beside it: a successful fill (GET, RESET's deferred first
# GET) initializes it wholly; EOF, PUT, REWRITE and CLOSE make it undefined;
# writes to F^ initialize what they write. PUT consumes the whole component
# (strict, like a value copy). Globals' files are covered too: the state
# belongs to the buffer, not to the file variable.
cat > "$work/files.pas" <<'PAS'
PROGRAM files;
TYPE R = RECORD a, b: INTEGER END;
VAR g: FILE OF R;
PROCEDURE cset(VAR v: INTEGER) [C]; EXTERN;
PROCEDURE probe;
VAR f: FILE OF INTEGER; t: TEXT; x: INTEGER; c: CHAR; r: R;
BEGIN
  {$INITCK+}
  REWRITE(f); f^ := 0; PUT(f); f^ := -32768; PUT(f); cset(f^); PUT(f);
  RESET(f); x := f^; GET(f); WRITELN(x, ' ', f^, ' ', EOF(f));
  GET(f); WRITELN(f^); GET(f); WRITELN(EOF(f));
  REWRITE(g); r.a := 1; r.b := 2; g^ := r; PUT(g); RESET(g); r := g^; WRITELN(r.a + r.b);
  REWRITE(t); WRITELN(t, 'hi'); t^ := '!'; PUT(t); RESET(t);
  c := t^; WRITELN(c, EOLN(t)); READLN(t); READ(t, c); WRITELN(c); CLOSE(t)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok files '0 -32768 FALSE\n7\nTRUE\n3\nhFALSE\n!\n'
# Exact failures: a buffer nothing has filled or written, a PUT of it, a PUT
# after PUT, a record buffer given a partial record (by an unchecked copy;
# the typechecker rejects selecting a field of a file buffer) then PUT or
# copied, and the buffer at EOF.
for kind in unwritten put putput partialput partialread eof; do
  case "$kind" in
    unwritten) body='REWRITE(f); x := f^'; what='component f^'; needle='f^ ' ;;
    put) body='REWRITE(f); PUT(f)'; what='part of f^'; needle='f)' ;;
    putput) body='REWRITE(f); f^ := 1; PUT(f); PUT(f)'; what='part of f^'; needle='f)' ;;
    partialput) body='REWRITE(g); r.a := 1; {$INITCK-} g^ := r; {$INITCK+} PUT(g)'; what='part of g^'; needle='g)' ;;
    partialread) body='REWRITE(g); r.a := 1; {$INITCK-} g^ := r; {$INITCK+} s := g^'; what='part of g^'; needle='g^ ' ;;
    eof) body='REWRITE(f); f^ := 1; PUT(f); RESET(f); GET(f); x := f^'; what='component f^'; needle='f^ ' ;;
  esac
  printf 'PROGRAM filebad;\nTYPE R = RECORD a, b: INTEGER END;\nPROCEDURE probe;\nVAR f: FILE OF INTEGER; g: FILE OF R; x: INTEGER; r, s: R;\nBEGIN {$INITCK+} %s {$INITCK-} END;\nBEGIN WRITELN(%s); probe END.\n' "$body" "'prefix'" > "$work/filebad.pas"
  expect_fail filebad 'prefix\n' "runtime error: INITCK uninitialized $what at line 5 column $(col "$work/filebad.pas" 5 "$needle")"
done
# IR: the buffer state is stored in the FCB beside the buffer (field 10,
# with its leaf count) and the PUT guard precedes the runtime's write.
bin/pascal1981 --dialect extended -O0 -S "$work/filebad.pas" -o "$work/filebad.ll"
python3 - "$work/filebad.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
probe = ir[ir.index('define void @probe('):]
probe = probe[:probe.index('\n}')]
assert re.search(r'%file_initck[0-9]* = alloca i1,', probe)
assert re.search(r'%file_initck[0-9]* = alloca \[2 x i1\]', probe)
assert 'store i32 2, ptr' in probe
assert probe.index('@pas_file_put(') > probe.index('initck.ready')
PY
# --- DEVICE code. ---
# DEVICE compilands (CPU-targeted or NVPTX) carry no INITCK state, so host
# instrumentation claims nothing there: every enabled read in one is the
# exact `DEVICE code` boundary. On the host, LAUNCH and the device runtime
# builtins read their operands as values; a typed pointer handed to a kernel
# releases its referent (the CPU device shares host memory), and host storage
# a device copy writes is reached through ADR, which released it.
cat > "$work/kinc.inc" <<'PAS'
DEVICE INTERFACE;
UNIT BUMPU (BUMP);
PROCEDURE BUMP(cell: ADS(GLOBAL) OF INTEGER);
END;
PAS
cat > "$work/kimpl.impl" <<'PAS'
(*$INCLUDE:'kinc.inc'*)
DEVICE IMPLEMENTATION OF BUMPU;
PROCEDURE BUMP(cell: ADS(GLOBAL) OF INTEGER);
BEGIN
  cell^ := 7
END;
.
PAS
cat > "$work/devhost.pas" <<'PAS'
{ DIALECT: extended }
(*$INCLUDE:'kinc.inc'*)
PROGRAM DEVHOST(output);
USES BUMPU (BUMP);
TYPE PINT = ^INTEGER;
PROCEDURE probe;
VAR cell: PINT; a, b: ARRAY [1..2] OF INTEGER; d: ADRMEM; grid, nbytes: INTEGER;
BEGIN
  {$INITCK+}
  NEW(cell); grid := 2;
  LAUNCH(BUMP, grid, 3, cell);
  WRITELN(cell^);
  a[1] := 4; a[2] := 5; nbytes := 4;
  d := DEVALLOC(nbytes); DEVCOPYTO(d, ADR a, nbytes); DEVCOPYFROM(ADR b, d, nbytes); DEVFREE(d);
  WRITELN(b[1] + b[2])
  {$INITCK-}
END;
BEGIN probe END.
PAS
for opt in 0 2; do
  (cd "$work" && "$OLDPWD/bin/pascal1981" -O"$opt" devhost.pas kimpl.impl -o devhost) > "$work/err" 2>&1 || { cat "$work/err" >&2; exit 1; }
  if [ -s "$work/err" ]; then cat "$work/err" >&2; exit 1; fi
  "$work/devhost" > "$work/actual" 2> "$work/err"
  printf '7\n9\n' | diff -u - "$work/actual"
  test ! -s "$work/err"
done
# Load-bearing: the host never writes cell^, so the checked read above
# passes only because LAUNCH released the referent before the launch call.
(cd "$work" && "$OLDPWD/bin/pascal1981" -O0 -S devhost.pas -o devhost.ll)
python3 - "$work/devhost.ll" <<'PY'
import sys
ir = open(sys.argv[1]).read()
probe = ir[ir.index('define void @probe('):]
rel = probe.index('call void @pas_initck_heap_release(')
assert rel < probe.index('@pas_dev_launch(')
PY
# Device compilands: one exact boundary for an enabled read, CPU and NVPTX.
python3 - > "$work/devread.pas" <<'PY'
s = open('tests/fixtures/initck_state_device.pas').read()
print(s.replace("c := 'a' END", "c := 'a'; {$INITCK+} x := x + 1 {$INITCK-} END"))
PY
for target in host nvptx; do
  opts=()
  if [ "$target" = nvptx ]; then opts=(--device-triple nvptx64-nvidia-cuda); fi
  rm -f "$work/devread.ll"
  if bin/pascal1981 --dialect extended "${opts[@]}" -O0 -S "$work/devread.pas" -o "$work/devread.ll" 2> "$work/err"; then
    echo "FAIL: $target DEVICE read accepted" >&2; exit 1
  fi
  printf 'INITCK unsupported boundary: DEVICE code at line 11 column %s\n' "$(col "$work/devread.pas" 11 'x + 1')" | diff -u - "$work/err"
  test ! -s "$work/devread.ll"
done
# --- Review regressions (port-initck review of edf9188). ---
# Untracked referents keep separate state: two VAR aliases of distinct
# released heap records, or of distinct C cells, do not share state bytes,
# so an unchecked write through one never fails a checked read through the
# other. A released or untracked referent still reads as initialized when it
# is looked up afresh.
cat > "$work/untracked.pas" <<'PAS'
PROGRAM untracked;
TYPE R = RECORD a: INTEGER END; P = ^R;
FUNCTION cmem: ADRMEM [C]; EXTERN;
FUNCTION cmem2: ADRMEM [C]; EXTERN;
PROCEDURE Two(VAR x, y: R);
VAR u: INTEGER;
BEGIN {$INITCK-} x.a := u; {$INITCK+} WRITELN(y.a) {$INITCK-} END;
PROCEDURE probe;
VAR p, q: P; ap, aq: ADRMEM;
BEGIN
  NEW(p); NEW(q); p^.a := 2; q^.a := 3; ap := p; aq := q;
  Two(p^, q^);
  p := cmem; q := cmem2; p^.a := 4; q^.a := 5;
  Two(p^, q^);
  {$INITCK+} WRITELN(q^.a) {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok untracked '3\n5\n5\n'
# Effects of a call happen at the call, after every actual is evaluated: a
# [C] VAR binding, a pointer value actual handed to [C] and an ADR actual do
# not make storage that a later actual reads initialized. Initialized
# twins pass the read value through.
cat > "$work/callorder.pas" <<'PAS'
PROGRAM callorder;
TYPE PI = ^INTEGER;
PROCEDURE cpair(VAR v: INTEGER; b: INTEGER) [C]; EXTERN;
PROCEDURE cptr(p: PI; b: INTEGER) [C]; EXTERN;
PROCEDURE cadr(a: ADRMEM; b: INTEGER) [C]; EXTERN;
PROCEDURE probe;
VAR x, y: INTEGER; q: PI;
BEGIN
  {$INITCK+}
  x := 4; cpair(x, x); WRITELN(x);
  NEW(q); q^ := 6; cptr(q, q^); WRITELN(q^);
  y := 8; cadr(ADR y, y); WRITELN(y)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok callorder '4\n6\n8\n'
for kind in var ptr adr; do
  case "$kind" in
    var) decl='PROCEDURE cpair(VAR v: INTEGER; b: INTEGER) [C]; EXTERN;'; body='cpair(x, x)'; what='local x'; needle='x)' ;;
    ptr) decl='PROCEDURE cptr(p: PI; b: INTEGER) [C]; EXTERN;'; body='NEW(q); cptr(q, q^)'; what='component q^'; needle='q^)' ;;
    adr) decl='PROCEDURE cadr(a: ADRMEM; b: INTEGER) [C]; EXTERN;'; body='cadr(ADR x, x)'; what='local x'; needle='x)' ;;
  esac
  printf 'PROGRAM orderbad;\nTYPE PI = ^INTEGER;\n%s\nPROCEDURE probe;\nVAR x: INTEGER; q: PI;\nBEGIN {$INITCK+} %s {$INITCK-} END;\nBEGIN WRITELN(%s); probe END.\n' "$decl" "$body" "'prefix'" > "$work/orderbad.pas"
  expect_fail orderbad 'prefix\n' "runtime error: INITCK uninitialized $what at line 6 column $(col "$work/orderbad.pas" 6 "$needle")"
done
# An actual's unchecked unset reads stay with what the callee receives: a
# [C] result, and the result of a Pascal function whose formal is untracked
# (REAL), are initialized even when the actual consumed an unset local.
cat > "$work/argscope.pas" <<'PAS'
PROGRAM argscope;
FUNCTION cfive(n: INTEGER): INTEGER [C]; EXTERN;
FUNCTION pfive(r: REAL): INTEGER; BEGIN pfive := 5 END;
PROCEDURE probe;
VAR u, y, z: INTEGER;
BEGIN
  {$INITCK-} y := cfive(u); z := pfive(u); {$INITCK+}
  WRITELN(y); WRITELN(z)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok argscope '5\n5\n'
# A checked read of a program-level variable in the main body is a global.
printf 'PROGRAM mainbnd;\nVAR g: INTEGER;\nBEGIN g := 1; {$INITCK+} WRITELN(g) {$INITCK-} END.\n' > "$work/mainbnd.pas"
for opt in 0 2; do
  if bin/pascal1981 --dialect extended -O"$opt" -S "$work/mainbnd.pas" -o "$work/mainbnd.ll" 2> "$work/err"; then
    echo 'FAIL: main-body global boundary accepted' >&2; exit 1
  fi
  printf 'INITCK unsupported boundary: global or captured storage at line 3 column %s\n' "$(col "$work/mainbnd.pas" 3 'g)')" | diff -u - "$work/err"
done

# --- Unsupported boundaries: one exact diagnostic per category. ---
# Every category the compiler can report, with the consuming token's
# location; the INITCK-disabled twin compiles cleanly (no other error can
# masquerade as the boundary) and neither is executed. DEVICE code is above.
# `selected storage` (selecting from a call result) is defensive: codegen
# rejects `f.x` on a niladic call and the parser has no `f(1).x`.
bnd() { # KIND LINE NEEDLE CATEGORY FR-SUFFIX BODY
  printf 'PROGRAM bnd;\nTYPE R = RECORD f: INTEGER END; Q = RECORD f: INTEGER; r: REAL END;\nVAR g: INTEGER; gq: Q;\nFUNCTION mk: R; VAR t: R; BEGIN t.f := 1; mk := t END;\nFUNCTION fr: REAL; BEGIN fr := 1.0 %s END;\nPROCEDURE probe;\nVAR x: INTEGER; y: REAL; r: R; p: ^REAL; h: FILE OF REAL; q: ADRMEM;\nBEGIN x := 1; y := 1.0; r.f := 1; NEW(p); p^ := 1.0;\n  %s\nEND;\nBEGIN probe END.\n' "$5" "$6" > "$work/bnd.pas"
  sed 's/{\$INITCK+}/{$INITCK-}/g' "$work/bnd.pas" > "$work/bnd-off.pas"
  bin/pascal1981 --dialect extended -O0 -S "$work/bnd-off.pas" -o "$work/bnd-off.ll" 2> "$work/err"
  test ! -s "$work/err"
  for opt in 0 2; do
    rm -f "$work/bnd.ll"
    if bin/pascal1981 --dialect extended -O"$opt" -S "$work/bnd.pas" -o "$work/bnd.ll" 2> "$work/err"; then
      echo "FAIL: $1 boundary accepted" >&2; exit 1
    fi
    printf 'INITCK unsupported boundary: %s at line %s column %s\n' "$4" "$2" "$(col "$work/bnd.pas" "$2" "$3")" | diff -u - "$work/err"
    test ! -s "$work/bnd.ll"
  done
}
bnd global 9 'g)' 'global or captured storage' '' '{$INITCK+} WRITELN(g) {$INITCK-}'
bnd untracked 9 'y:3' 'untracked type' '' '{$INITCK+} WRITELN(y:3:1) {$INITCK-}'
bnd escaped 9 'r.f)' 'escaped local or formal' '' 'WITH r DO q := ADR f; {$INITCK+} WRITELN(r.f) {$INITCK-}'
bnd withtarget 9 'f)' 'untracked WITH target' '' 'WITH gq DO BEGIN {$INITCK+} WRITELN(f) {$INITCK-} END'
bnd unresolved 9 'x)' 'unresolved WITH target' '' 'WITH mk DO BEGIN {$INITCK+} WRITELN(x) {$INITCK-} END'
bnd heap 9 'p^' 'heap storage' '' '{$INITCK+} WRITELN(p^:3:1) {$INITCK-}'
bnd filebuffer 9 'h^:' 'file buffer' '' 'REWRITE(h); h^ := 1.0; {$INITCK+} WRITELN(h^:3:1) {$INITCK-}'
bnd fileput 9 'h)' 'file buffer' '' 'REWRITE(h); h^ := 1.0; {$INITCK+} PUT(h) {$INITCK-}'
bnd result 5 'END' 'function result' '{$INITCK+}' ''
bnd call 9 'PRED' 'call consumer' '' '{$INITCK+} WRITELN(PRED(x)) {$INITCK-}'
bnd expression 9 '\[x\]' 'unsupported expression' '' '{$INITCK+} WRITELN(x IN [x]) {$INITCK-}'
echo 'PASS: INITCK external boundaries: C calls, raw addresses, descriptors, files, DEVICE code and diagnostics'
