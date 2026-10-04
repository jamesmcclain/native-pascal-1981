#!/usr/bin/env bash
# INITCK aggregates: fixed ARRAYs and RECORDs built only from INTEGER, BOOLEAN
# and CHAR leaves carry one shadow state per scalar leaf, so writing one
# component never initializes its neighbors. Never run unchecked bad reads as
# if their output meant anything.
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

# at NAME LINE TEXT: 1-based column of the first TEXT on LINE of NAME.pas.
at() {
  local col
  col=$(sed -n "$2p" "$work/$1.pas" | grep -bo -F -- "$3" | head -1 | cut -d: -f1)
  echo "line $2 column $((col + 1))"
}

# --- Element/field granularity: fixed arrays, records, nesting, indexing. ---
cat > "$work/grain-ok.pas" <<'PAS'
PROGRAM grainok;
TYPE P = RECORD x, y: INTEGER; c: CHAR; ok: BOOLEAN END;
     Row = ARRAY [0..1] OF P;
     Grid = ARRAY [1..3] OF Row;
     Box = RECORD tag: CHAR; v: ARRAY [1..4] OF INTEGER; inner: P END;
PROCEDURE probe(k: INTEGER);
VAR a: ARRAY [1..4] OF INTEGER; r: P; g: Grid; b: Box;
    seen: ARRAY [CHAR] OF BOOLEAN; i, j: INTEGER; ch: CHAR;
BEGIN
  {$INITCK+}
  a[1] := 0; i := 2; a[i] := a[1] - 32767 - 1;
  r.x := 7; r.c := 'z'; r.ok := FALSE;
  FOR i := 1 TO 3 DO
    FOR j := 0 TO 1 DO g[i][j].y := i * 10 + j;
  g[k][1].x := g[2][0].y;
  b.v[k + 1] := 5; b.inner.c := 'n'; b.tag := b.inner.c;
  ch := 'q'; seen[ch] := TRUE;
  WRITELN(a[1], ' ', a[2], ' ', r.x, r.c, ORD(r.ok), ' ', g[3][1].y, ' ',
          g[k][1].x, ' ', b.v[k + 1], b.tag, ORD(seen['q']))
END;
BEGIN probe(1); probe(3) END.
PAS
expect_ok grain-ok '0 -32768 7z0 31 20 5n1\n0 -32768 7z0 31 20 5n1\n'

# One write never initializes a neighbor: element, field, nested and dynamic.
for kind in element field nested dynamic deep char; do
  case "$kind" in
    element) decl='a: ARRAY [1..3] OF INTEGER'; body='a[1] := 1'; read='a[2]'; what='a[2]' ;;
    field) decl='r: RECORD x, y: INTEGER END'; body='r.x := 1'; read='r.y'; what='r.y' ;;
    nested) decl='m: ARRAY [1..2] OF RECORD v: ARRAY [1..2] OF BOOLEAN END'
      body='m[2].v[1] := TRUE'; read='ORD(m[2].v[2])'; what='m[2].v[2]' ;;
    dynamic) decl='a: ARRAY [1..5] OF INTEGER; i: INTEGER'
      body='FOR i := 1 TO 3 DO a[i] := i; i := 4'; read='a[i]'; what='a[i]' ;;
    deep) decl='m: ARRAY [1..2] OF ARRAY [1..2] OF CHAR'; body="m[1][2] := 'x'; m[2][1] := 'y'"
      read='m[1][1]'; what='m[1][1]' ;;
    char) decl='s: ARRAY [CHAR] OF INTEGER'; body="s['a'] := 1"; read="s[CHR(ORD('a') + 1)]"; what='s[...]' ;;
  esac
  cat > "$work/grain-bad.pas" <<PAS
PROGRAM grainbad;
PROCEDURE probe;
VAR $decl;
BEGIN
  $body; WRITELN('prefix');
  {\$INITCK+} WRITELN($read); {\$INITCK-}
  WRITELN('after')
END;
BEGIN probe END.
PAS
  root=${what%%[[.]*}
  expect_fail grain-bad 'prefix\n' "runtime error: INITCK uninitialized component $what at $(at grain-bad 6 "$root")"
done

# Each activation starts with every leaf unset, including recursion.
cat > "$work/recur-bad.pas" <<'PAS'
PROGRAM recurbad;
PROCEDURE down(n: INTEGER);
VAR a: ARRAY [1..2] OF INTEGER;
BEGIN
  IF n > 0 THEN BEGIN a[1] := n; down(n - 1) END
  ELSE BEGIN {$INITCK+} WRITELN(a[1]) {$INITCK-} END
END;
BEGIN WRITELN('prefix'); down(2) END.
PAS
expect_fail recur-bad 'prefix\n' "runtime error: INITCK uninitialized component a[1] at $(at recur-bad 6 'a[1]')"

# --- Producers: disabled writes, READ/READLN and unchecked copies. ---
cat > "$work/produce-ok.pas" <<'PAS'
PROGRAM produceok;
PROCEDURE probe;
VAR a: ARRAY [1..3] OF INTEGER; r: RECORD c: CHAR; b: BOOLEAN END;
    t: ARRAY [1..2] OF INTEGER; i, y: INTEGER;
BEGIN
  {$INITCK-} a[1] := 4; r.b := TRUE; t[1] := a[1]; y := t[1] + a[1];
  i := 2; READLN(a[i]); READ(r.c);
  {$INITCK+} WRITELN(a[1], ' ', a[2], ' ', r.c, ORD(r.b), ' ', t[1], ' ', y)
  {$INITCK-}
END;
BEGIN probe END.
PAS
expect_ok produce-ok '4 -32768 q1 4 8\n' '-32768\nq\n'

for kind in copy compcopy index read; do
  input=''
  case "$kind" in
    # An unchecked read of an unset component taints its destination.
    copy) decl='a: ARRAY [1..2] OF INTEGER; y: INTEGER'; body='a[1] := 1; y := a[2] + 0'
      read='y'; err="local y" ;;
    compcopy) decl='a, b: ARRAY [1..2] OF INTEGER'; body='a[1] := 1; b[1] := a[2]; b[2] := a[1]'
      read='b[1]'; err="component b[1]" ;;
    # An unchecked index with unset state taints the value it selects,
    # although the element itself is set (u * 0 is deterministic).
    index) decl='a: ARRAY [1..2] OF INTEGER; i, u, y: INTEGER'; body='a[1] := 1; i := (u * 0) + 1; y := a[i]'
      read='y'; err="local y" ;;
    # READ initializes exactly its own destination.
    read) decl='a: ARRAY [1..2] OF CHAR'; body='READ(a[1])'; read='a[2]'; err="component a[2]"; input='xy\n' ;;
  esac
  cat > "$work/produce-bad.pas" <<PAS
PROGRAM producebad;
PROCEDURE probe;
VAR $decl;
BEGIN
  $body; WRITELN('prefix');
  {\$INITCK+} WRITELN($read); {\$INITCK-}
  WRITELN('after')
END;
BEGIN probe END.
PAS
  root=${read%%[[ ]*}
  expect_fail produce-bad 'prefix\n' "runtime error: INITCK uninitialized $err at $(at produce-bad 6 "$root")" "$input"
done

# --- Ordering: bounds before INITCK; guard before the native load. ---
cat > "$work/order-bad.pas" <<'PAS'
PROGRAM orderbad;
PROCEDURE probe;
VAR a: ARRAY [1..3] OF INTEGER; i: INTEGER;
BEGIN
  i := 4; WRITELN('prefix');
  {$INITCK+} WRITELN(a[i]) {$INITCK-}
END;
BEGIN probe END.
PAS
expect_fail order-bad 'prefix\n' 'runtime error: array index 4 is outside bounds 1..3'

cat > "$work/order-ir.pas" <<'PAS'
PROGRAM orderir;
PROCEDURE probe;
VAR a: ARRAY [1..3] OF INTEGER; i, y: INTEGER;
BEGIN
  a[2] := 0; i := 2;
  {$INITCK+} y := a[i] {$INITCK-}
END;
BEGIN probe END.
PAS
bin/pascal1981 -O0 -S "$work/order-ir.pas" -o "$work/order-ir.ll"
# The element shadow is selected with the bounds-checked offset, then
# branched on, and only the ok block loads the element.
awk '
  /^define void @probe/ { on=1 }
  on && /^}/ { exit }
  on && /^index\.ok[0-9]*:/ { lastok=NR }
  on && /%initck\.elem[0-9]* = getelementptr \[3 x i1\], ptr %initck\.a, i32 0, i64 %/ { elem=NR; ok=lastok }
  on && /%initck\.ready[0-9]* = load i1, ptr %initck\.elem/ { ready=NR }
  on && /call void @pas_initck_fail/ { fail=NR }
  on && /load i16, ptr %[0-9]+/ && fail && !data { data=NR }
  END { exit !(ok && elem > ok && ready > elem && fail > ready && data > fail) }
' "$work/order-ir.ll"
grep -q 'store \[3 x i1\] zeroinitializer, ptr %initck\.a' "$work/order-ir.ll"

# --- Aggregate copies: strict checked transfers, exact unchecked propagation. ---
cat > "$work/copy-ok.pas" <<'PAS'
PROGRAM copyok;
TYPE P = RECORD x, y: INTEGER; c: CHAR END;
     V = ARRAY [1..3] OF P;
VAR g: P;
FUNCTION sum(q: P): INTEGER;
BEGIN {$INITCK+} sum := q.x + q.y {$INITCK-} END;
FUNCTION firstx(w: V): INTEGER;
BEGIN {$INITCK+} firstx := w[1].x {$INITCK-} END;
FUNCTION mk(n: INTEGER): P;
VAR t: P;
BEGIN t.x := n; t.y := n; t.c := 'm'; mk := t END;
PROCEDURE probe;
VAR a, b, e: P; v, w: V; i: INTEGER;
BEGIN
  {$INITCK+}
  a.x := 0; a.y := -32768; a.c := 'a';
  b := a;                         { checked, complete }
  v[2] := b; v[1].x := 9;         { record into element; partial array }
  {$INITCK-} w := v; {$INITCK+}   { unchecked partial copy keeps states }
  i := 2; e := w[i];              { checked copy of a complete element }
  a := a;                         { checked self-copy }
  g := e; {$INITCK-} e := g; {$INITCK+}  { untracked global round trip }
  b := mk(5);                     { untracked call result }
  {$INITCK-} i := firstx(w); {$INITCK+}  { partial value actual, transported }
  WRITELN(b.x, ' ', e.y, ' ', w[2].c, ' ', w[1].x, ' ', sum(v[2]), ' ',
          i, ' ', a.y, b.c)
END;
BEGIN probe END.
PAS
expect_ok copy-ok '5 -32768 a 9 -32768 9 -32768m\n'

for kind in checked partial self element sub actual callee index; do
  decls='TYPE P = RECORD x, y: INTEGER END; V = ARRAY [1..2] OF P;'
  routines='FUNCTION gety(q: P): INTEGER; BEGIN {$INITCK+} gety := q.y {$INITCK-} END;'
  case "$kind" in
    # A checked whole read needs every transferred leaf, before the load.
    checked) body='a.x := 1; {$INITCK+} b := a {$INITCK-}'; read='1'; err="part of a"; mark='a {'; line=8 ;;
    # An unchecked copy never blesses a missing leaf.
    partial) body='a.x := 1; b := a'; read='b.y'; err='component b.y'; mark='b.y'; line=9 ;;
    self) body='a.x := 1; a := a'; read='a.y'; err='component a.y'; mark='a.y'; line=9 ;;
    element) body='a.x := 1; v[2] := a; b := v[2]'; read='b.y'; err='component b.y'; mark='b.y'; line=9 ;;
    sub) body='v[1].x := 1; v[1].y := 2; v[2].x := 3; {$INITCK+} b := v[2] {$INITCK-}'; read='1'
      err='part of v[2]'; mark='v[2] {'; line=8 ;;
    # A checked value actual is read at the caller; an unchecked one carries
    # its leaves to the callee, which fails only at its own checked read.
    actual) body='a.x := 1; {$INITCK+} WRITELN(gety(a)) {$INITCK-}'; read='1'; err='part of a'; mark='a))'; line=8 ;;
    callee) body='a.x := 1; WRITELN(gety(a))'; read='1'; err='component q.y'; mark='q.y'; line=3 ;;
    # Unset state consumed while selecting the source unsets the copy.
    index) body='v[1].x := 1; v[1].y := 2; i := (u * 0) + 1; b := v[i]'; read='b.x'; err='component b.x'; mark='b.x'; line=9 ;;
  esac
  cat > "$work/copy-bad.pas" <<PAS
PROGRAM copybad;
$decls
$routines
PROCEDURE probe;
VAR a, b: P; v: V; i, u: INTEGER;
BEGIN
  WRITELN('prefix');
  $body;
  {\$INITCK+} WRITELN($read); {\$INITCK-}
  WRITELN('after')
END;
BEGIN probe END.
PAS
  expect_fail copy-bad 'prefix\n' "runtime error: INITCK uninitialized $err at $(at copy-bad $line "$mark")"
done

# The checked source is verified before its native load; unchecked copies
# store the data first, then transfer the leaf states.
cat > "$work/copy-ir.pas" <<'PAS'
PROGRAM copyir;
TYPE P = RECORD x, y: INTEGER END;
PROCEDURE probe;
VAR a, b, c: P;
BEGIN
  a.x := 1; a.y := 2;
  {$INITCK+} b := a; {$INITCK-} c := a
END;
BEGIN probe END.
PAS
bin/pascal1981 -O0 -S "$work/copy-ir.pas" -o "$work/copy-ir.ll"
awk '
  /^define void @probe/ { on=1 }
  on && /^}/ { exit }
  on && /call i32 @pas_initck_all\(ptr %initck\.a, i64 2\)/ && !all { all=NR }
  on && /call void @pas_initck_fail/ && !fail { fail=NR }
  on && /load .*, ptr %a, align/ && fail && !load1 { load1=NR; next }
  on && /store .*, ptr %b, align/ && load1 && !st1 { st1=NR }
  on && /call void @pas_initck_copy\(ptr %initck\.b, ptr %initck\.a, i64 2, i32/ { cp1=NR }
  on && /store .*, ptr %c, align/ && cp1 && !st2 { st2=NR }
  on && /call void @pas_initck_copy\(ptr %initck\.c, ptr %initck\.a, i64 2, i32/ && st2 { cp2=NR }
  END { exit !(all && fail > all && load1 > fail && st1 > load1 && cp1 > st1 && st2 > cp1 && cp2 > st2) }
' "$work/copy-ir.ll"

# --- Variant records: each field of each alternative has its own state. A
# tag is an ordinary field; no tag or active-variant checking is implied. ---
VARIANT_TYPES="TYPE Shape = RECORD id: CHAR; CASE kind: INTEGER OF 1: (r: INTEGER); 2: (w, h: INTEGER); 3: () END;
     Box = RECORD id: CHAR; CASE kind: INTEGER OF 1: (r: INTEGER); 2: (w, h: INTEGER) END;
     Pun = RECORD CASE BOOLEAN OF TRUE: (i: INTEGER); FALSE: (c: CHAR) END;
     Pair = RECORD CASE t: BOOLEAN OF TRUE: (a: INTEGER); FALSE: (b: CHAR) END;
     Shapes = ARRAY [1..2] OF Shape; Pairs = ARRAY [1..2] OF Pair;"
cat > "$work/variant-ok.pas" <<PAS
PROGRAM variantok;
$VARIANT_TYPES
PROCEDURE probe;
VAR s, t, u, v, q: Shape; p: Pun; ss, tt: Shapes; ps, pt: Pairs;
BEGIN
  {\$INITCK+}
  s.id := 'a'; s.kind := 2; s.w := 3; s.h := 4;
  t := s;                        { fixed fields and alternative 2 complete }
  s.kind := 1;                   { a tag change neither initializes nor invalidates }
  u.id := 'e'; u.kind := 3; v := u;   { an empty alternative is complete }
  ss[1] := t; ss[2] := u; tt := ss;   { element-wise check of an array }
  ps[1].t := TRUE; ps[1].a := 7; ps[2].t := FALSE; ps[2].b := 'z'; pt := ps;
  q.r := 9; {\$INITCK-} t := q; {\$INITCK+}   { unchecked: states copied as-is }
  p.c := 'k';
  WRITELN(s.w * s.h, ' ', s.kind, ' ', v.id, v.kind, ' ', tt[1].h, tt[2].id, ' ',
          pt[1].a, pt[2].b, ' ', t.r, ' ', p.c)
END;
BEGIN probe END.
PAS
expect_ok variant-ok '12 1 e3 4e 7z 9 k\n'

for kind in otherarm pun tag tagonly partialarm tagunset array; do
  case "$kind" in
    # Overlapping storage is not credited across alternatives.
    otherarm) body='s.kind := 1; s.r := 5'; read='s.w'; err='component s.w'; mark='s.w' ;;
    pun) body='p.i := 65'; read='p.c'; err='component p.c'; mark='p.c' ;;
    # A tag and its alternatives are independent fields.
    tag) body='s.r := 1'; read='s.kind'; err='component s.kind'; mark='s.kind' ;;
    tagonly) body='s.kind := 2'; read='s.w'; err='component s.w'; mark='s.w' ;;
    # A checked transfer needs the fixed fields and one complete alternative.
    partialarm) body="s.id := 'a'; s.kind := 2; s.w := 1"; read='1); t := s; WRITELN(2'; err='part of s'; mark='s; WRITELN' ;;
    tagunset) body="s.id := 'a'; s.r := 1"; read='1); t := s; WRITELN(2'; err='part of s'; mark='s; WRITELN' ;;
    array) body='ps[1].t := TRUE; ps[1].a := 1; ps[2].t := FALSE'; read='1); pt := ps; WRITELN(2'
      err='part of ps'; mark='ps; WRITELN' ;;
  esac
  cat > "$work/variant-bad.pas" <<PAS
PROGRAM variantbad;
$VARIANT_TYPES
PROCEDURE probe;
VAR s, t: Box; p: Pun; ps, pt: Pairs;
BEGIN
  $body; WRITELN('prefix');
  {\$INITCK+} WRITELN($read); {\$INITCK-}
  WRITELN('after')
END;
BEGIN probe END.
PAS
  line=$(grep -n 'WRITELN(.prefix.)' "$work/variant-bad.pas" | cut -d: -f1)
  line=$((line + 1))
  prefix='prefix\n'
  case "$kind" in partialarm|tagunset|array) prefix='prefix\n1\n' ;; esac
  expect_fail variant-bad "$prefix" "runtime error: INITCK uninitialized $err at $(at variant-bad $line "$mark")"
done

# --- Aliases: VAR/CONST formals and WITH share the storage's own leaves. ---
ALIAS_DECLS="TYPE P = RECORD x, y: INTEGER END; V = ARRAY [1..3] OF INTEGER; M = ARRAY [1..2] OF P;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE swap(VAR a, b: INTEGER);
VAR t: INTEGER;
BEGIN {\$INITCK+} t := a; a := b; b := t {\$INITCK-} END;
PROCEDURE bump(VAR n: INTEGER);
BEGIN {\$INITCK+} n := n + 1 {\$INITCK-} END;
PROCEDURE fill(VAR w: V; k: INTEGER);
VAR i: INTEGER;
BEGIN FOR i := 1 TO 3 DO w[i] := k * i END;
PROCEDURE fill1(VAR w: V);
BEGIN w[1] := 1 END;
PROCEDURE setp(VAR q: P);
BEGIN q.x := 1; q.y := 2 END;
PROCEDURE fwd(VAR q: P);
BEGIN setp(q) END;
FUNCTION sumc(CONST w: V): INTEGER;
BEGIN {\$INITCK+} sumc := w[1] + w[2] + w[3] {\$INITCK-} END;
FUNCTION third(CONST w: V): INTEGER;
BEGIN {\$INITCK+} third := w[3] {\$INITCK-} END;
FUNCTION get(VAR n: INTEGER): INTEGER;
BEGIN {\$INITCK+} get := n {\$INITCK-} END;
FUNCTION whole(VAR w: V): INTEGER;
VAR t: V;
BEGIN {\$INITCK+} t := w; {\$INITCK-} whole := t[1] END;
PROCEDURE zap(VAR w: V);
BEGIN fillc(ADR w, 6, CHR(0)) END;"
cat > "$work/alias-ok.pas" <<PAS
PROGRAM aliasok;
$ALIAS_DECLS
VAR gv: V;
PROCEDURE probe;
VAR a, z, e: V; m: M; r: P; i: INTEGER;
BEGIN
  {\$INITCK+}
  a[1] := 5; a[2] := 7; swap(a[1], a[2]); bump(a[2]);   { leaf bindings }
  fill(z, 2);                                          { whole aggregate }
  setp(m[2]); fwd(r);                                  { sub-aggregate, forwarded }
  WITH m[1] DO BEGIN x := r.x; y := x + 1 END;         { WITH binds field leaves }
  WITH r DO y := y * 10;
  i := 1; WITH m[i + 1] DO x := x + 100;
  {\$INITCK-} fill(gv, 1); {\$INITCK+}                  { untracked: private leaves }
  zap(e);                                              { escaped formal releases }
  WRITELN(a[1], ' ', a[2], ' ', sumc(z), ' ', m[1].x, m[1].y, ' ', r.y, ' ',
          m[2].x, ' ', e[3], ' ', whole(z))
END;
BEGIN probe END.
PAS
expect_ok alias-ok '7 6 12 12 20 101 0 2\n'

for kind in varleaf varpartial varwhole constread withread withfield withsub; do
  case "$kind" in
    # A callee's checked read through a binding checks the caller's leaf.
    varleaf) body='a[1] := 1; i := get(a[2])'; err='parameter n'; at_line=23; mark='n {' ;;
    # A callee's writes initialize exactly the leaves it wrote.
    varpartial) body='fill1(a); WRITELN(a[2])'; err='component a[2]'; at_line=33; mark='a[2]' ;;
    varwhole) body='fill1(a); i := whole(a)'; err='part of w'; at_line=26; mark='w;' ;;
    constread) body='fill1(a); i := third(a)'; err='component w[3]'; at_line=21; mark='w[3]' ;;
    # WITH writes a field's own leaf; its siblings stay unset.
    withread) body='WITH r DO x := 1; WRITELN(r.y)'; err='component r.y'; at_line=33; mark='r.y' ;;
    withfield) body='WITH r DO BEGIN x := 1; WRITELN(y) END'; err='field y'; at_line=33; mark='y)' ;;
    withsub) body='WITH m[2] DO x := 1; WRITELN(m[2].y)'; err='component m[2].y'; at_line=33; mark='m[2].y' ;;
  esac
  cat > "$work/alias-bad.pas" <<PAS
PROGRAM aliasbad;
$ALIAS_DECLS
PROCEDURE probe;
VAR a: V; m: M; r: P; i: INTEGER;
BEGIN
  WRITELN('prefix');
  {\$INITCK+} $body {\$INITCK-};
  WRITELN('after')
END;
BEGIN probe END.
PAS
  expect_fail alias-bad 'prefix\n' "runtime error: INITCK uninitialized $err at $(at alias-bad $at_line "$mark")"
done

# WITH-bound names are validated against the bound fields: a tracked field
# wins over a same-named untracked local, and an untracked field is a boundary
# for output and builtin consumers alike (never an unguarded address use).
cat > "$work/withname-ok.pas" <<'PAS'
PROGRAM withnameok;
TYPE P = RECORD x, y: INTEGER END;
PROCEDURE probe;
VAR x: REAL; r: P;
BEGIN
  x := 1.5; r.x := 4;
  {$INITCK+} WITH r DO WRITELN(x) {$INITCK-};
  WRITELN(x:3:1)
END;
BEGIN probe END.
PAS
expect_ok withname-ok '4\n1.5\n'
for use in 'WRITELN(s)' 'CONCAT(s, s)'; do
  printf 'PROGRAM withname;\nTYPE Q = RECORD n: INTEGER; s: LSTRING(4) END;\nPROCEDURE probe;\nVAR q: Q;\nBEGIN q.s := %s; {$INITCK+} WITH q DO %s {$INITCK-} END;\nBEGIN probe END.\n' \
    "'ab'" "$use" > "$work/withname.pas"
  if bin/pascal1981 -O0 -S "$work/withname.pas" -o "$work/withname.ll" 2> "$work/err"; then
    echo "FAIL: untracked WITH field accepted: $use" >&2; exit 1
  fi
  printf 'INITCK unsupported boundary: untracked WITH target\n' > "$work/expected-err"
  sed -E 's/ at line [0-9]+ column [0-9]+$//' "$work/err" | diff -u "$work/expected-err" -
done

# --- Representations. PACKED arrays/records are rejected by codegen with or
# without INITCK. Strings (including LSTRING .LEN, element 0 of the same
# storage), sets and vectors (including BOOLEAN vectors) are never tracked,
# nor is an aggregate holding one, so an enabled read of their components is
# an exact boundary; the INITCK-disabled twin compiles cleanly. Overlapping
# variant storage follows the logical-field model above. ---
for kind in packedarr packedrec lstr lstrlen str set vec boolvec mixed; do
  header=''; category='INITCK unsupported boundary: untracked type'
  case "$kind" in
    packedarr) local='x: PACKED ARRAY [1..4] OF CHAR'; setup="x[1] := 'a'"; expr='x[1]'
      category='codegen: PACKED arrays are not supported' ;;
    packedrec) header='TYPE R = PACKED RECORD a, b: BOOLEAN END;'; local='x: R'; setup='x.a := TRUE'
      expr='ORD(x.a)'; category='codegen: PACKED records are not supported' ;;
    lstr) local='x: LSTRING(4)'; setup="x := 'ab'"; expr='x[1]' ;;
    lstrlen) local='x: LSTRING(4)'; setup="x := 'ab'"; expr='ORD(x.LEN)' ;;
    str) local='x: STRING(4)'; setup="x := 'abcd'"; expr='x[1]' ;;
    set) local='x: SET OF 0..9'; setup='x := [1]'; expr='ORD(1 IN x)' ;;
    vec) header='TYPE V4 = VECTOR [4] OF INTEGER32;'; local='x: V4'; setup='x[0] := 1'; expr='x[0]' ;;
    boolvec) header='TYPE B4 = VECTOR [4] OF BOOLEAN;'; local='x: B4'; setup='x[0] := TRUE'; expr='ORD(x[0])' ;;
    mixed) header='TYPE R = RECORD n: INTEGER; s: LSTRING(4) END;'; local='x: R'; setup='x.n := 1'; expr='x.n' ;;
  esac
  printf 'PROGRAM rep;\n%s\nPROCEDURE probe;\nVAR %s;\nBEGIN %s; {$INITCK+} WRITELN(%s) {$INITCK-} END;\nBEGIN probe END.\n' \
    "$header" "$local" "$setup" "$expr" > "$work/rep.pas"
  sed 's/{\$INITCK+}/{$INITCK-}/' "$work/rep.pas" > "$work/rep-off.pas"
  for opt in 0 2; do
    rm -f "$work/rep.ll"
    if bin/pascal1981 --dialect extended -O"$opt" -S "$work/rep.pas" -o "$work/rep.ll" 2> "$work/err"; then
      echo "FAIL: $kind representation accepted" >&2; exit 1
    fi
    printf '%s\n' "$category" > "$work/expected-err"
    sed -E 's/ at line [0-9]+ column [0-9]+$//' "$work/err" | diff -u "$work/expected-err" -
    test ! -s "$work/rep.ll"
  done
  case "$kind" in
    packed*) ! bin/pascal1981 --dialect extended -S "$work/rep-off.pas" -o "$work/rep-off.ll" 2> /dev/null ;;
    *) bin/pascal1981 --dialect extended -S "$work/rep-off.pas" -o "$work/rep-off.ll" 2> "$work/err"
       test ! -s "$work/err" ;;
  esac
done

# --- Instrumented indexing evaluates each index exactly once and keeps the
# existing bounds-check order: every designator below calls next once, in
# reads, writes, READ, VAR bindings, WITH targets, copies (both sides) and
# with INDEXCK disabled. ---
cat > "$work/once-ok.pas" <<'PAS'
PROGRAM onceok;
TYPE R = RECORD x, y: INTEGER END;
VAR calls: INTEGER;
FUNCTION next: INTEGER;
BEGIN calls := calls + 1; next := 1 + calls MOD 2 END;
PROCEDURE bump(VAR n: INTEGER);
BEGIN n := n + 1 END;
PROCEDURE probe;
VAR a: ARRAY [1..2] OF INTEGER; r, s: ARRAY [1..2] OF R; y: INTEGER;
BEGIN
  {$INITCK+}
  a[1] := 0; a[2] := 0; s[1].x := 1; s[1].y := 2; s[2] := s[1];
  a[next] := 5; y := a[next]; READ(a[next]); bump(a[next]);
  WITH r[next] DO BEGIN x := 3; y := 4 END;
  r[next] := s[next];
  {$INDEXCK-} y := y + a[next]; {$INDEXCK+}
  WRITELN(y, ' ', a[1], ' ', a[2], ' ', r[1].x + r[2].x)
  {$INITCK-}
END;
BEGIN calls := 0; probe; WRITELN(calls) END.
PAS
expect_ok once-ok '1 1 7 4\n8\n' '7\n'

# A failing guard or bounds check follows exactly one evaluation.
cat > "$work/once-bad.pas" <<'PAS'
PROGRAM oncebad;
FUNCTION next(k: INTEGER): INTEGER;
BEGIN WRITELN('next'); next := k END;
PROCEDURE probe(k: INTEGER);
VAR a: ARRAY [1..3] OF INTEGER;
BEGIN
  a[1] := 1;
  {$INITCK+} WRITELN(a[next(k)]) {$INITCK-}
END;
BEGIN probe(1); probe(2) END.
PAS
expect_fail once-bad 'next\n1\nnext\n' "runtime error: INITCK uninitialized component a[...] at $(at once-bad 8 'a[')"
sed -i 's/probe(1); probe(2)/probe(4)/' "$work/once-bad.pas"
expect_fail once-bad 'next\n' 'runtime error: array index 4 is outside bounds 1..3'

# With INDEXCK disabled there is no bounds check; the element shadow still
# reuses the data GEP's own offset value.
cat > "$work/once-ir.pas" <<'PAS'
PROGRAM onceir;
PROCEDURE probe(i: INTEGER);
VAR a: ARRAY [1..3] OF INTEGER; y: INTEGER;
BEGIN
  {$INDEXCK-} a[1] := 0;
  {$INITCK+} y := a[i] {$INITCK-}
END;
BEGIN probe(1) END.
PAS
bin/pascal1981 -O0 -S "$work/once-ir.pas" -o "$work/once-ir.ll"
awk '
  /^define void @probe/ { on=1 }
  on && /^}/ { exit }
  on && /= getelementptr \[3 x i16\], ptr %a, i32 0, i[0-9]+ %/ { n=split($0, f, " "); data=f[n] }
  on && /%initck\.elem[0-9]* = getelementptr \[3 x i1\], ptr %initck\.a, i32 0, i[0-9]+ %/ { n=split($0, f, " "); elem=f[n] }
  on && /index\.(ok|bad)/ { bounds=1 }
  END { exit !(data != "" && data == elem && !bounds) }
' "$work/once-ir.ll"

# --- Boundaries: aggregates with untracked leaves and unmodeled whole uses
# are covered by initck_scalar.sh's exact boundary loop. ---

echo 'PASS: INITCK aggregates: element/field granularity, nesting, dynamic indexing, producers, copies, variants, aliases, representations, single evaluation'
