#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
require bin/pascal1981 runtime/build/libpascalrt.a
# INITCK scalar producers beyond literal assignment.
#
# Unchecked copies carry
# their source state, READ/READLN destinations and FOR control variables are
# producers. Never run unchecked bad reads as if their output meant anything.

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
cp tests/contract/fixtures/initck_producers/copy-ok.pas "$work/copy-ok.pas"
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
cp tests/contract/fixtures/initck_producers/copy-ir.pas "$work/copy-ir.pas"
bin/pascal1981 -O0 -S "$work/copy-ir.pas" -o "$work/copy-ir.ll"
python3 tests/contract/fixtures/initck_producers/copy-ir.py "$work/copy-ir.ll"

# --- READ/READLN: successful conversion initializes direct destinations. ---
cp tests/contract/fixtures/initck_producers/read-ok.pas "$work/read-ok.pas"
expect_ok read-ok '-32767x1\n0y\n' '-32768xTRUE\n0y\n'
# A READ of one destination does not initialize another.
cp tests/contract/fixtures/initck_producers/read-bad.pas "$work/read-bad.pas"
expect_fail read-bad '5\n' 'runtime error: INITCK uninitialized local m at line 7 column 11' '5\n'
# Status gating: success sets state; a trapped file failure keeps the prior
# state and leaves destinations uncorrupted.
cp tests/contract/fixtures/initck_producers/read-ir.pas "$work/read-ir.pas"
bin/pascal1981 -O0 -S "$work/read-ir.pas" -o "$work/read-ir.ll"
python3 tests/contract/fixtures/initck_producers/read-ir.py "$work/read-ir.ll"

# Trapped file READ destination preservation execution contract. Pascal has
# no F.TRAP selector yet, so a C helper sets it. A FILE variable holds the
# FCB pointer (LoadFileFcbPtr), so ADR f is a struct pas_file_fcb **. The
# helper checks that it reached a TEXT FCB open for reading before it
# writes, so a layout change fails here with a message instead of
# corrupting memory.
command -v "${CC:-clang}" > /dev/null || die "${CC:-clang} is needed to build the trap helper"
cat > "$work/trap_helper.c" << 'C_EOF'
#include <stdio.h>
#include <stdlib.h>
#include "pascalrt.h"
void set_file_trap(struct pas_file_fcb **f) {
  if (!f || !*f || (*f)->structure != STRUCT_TEXT
      || ((*f)->mode & MODE_BITS) != MODE_READ) {
    fputs("set_file_trap: ADR f is not a pas_file_fcb ** of a TEXT file open for reading\n", stderr);
    exit(2);
  }
  (*f)->trap = 1;
}
C_EOF
"${CC:-clang}" -c -I runtime "$work/trap_helper.c" -o "$work/trap_helper.o"

cat > "$work/trapped_read.pas" << 'PAS_EOF'
PROGRAM traptest(OUTPUT);
TYPE Color = (RED, GREEN, BLUE);
PROCEDURE set_file_trap(fcb: ADRMEM); EXTERN;
VAR
  f: TEXT;
  c: Color;
  b: BOOLEAN;
  p: ^INTEGER;
  dummy: INTEGER;
BEGIN
  ASSIGN(f, 'traptest.tmp');
  REWRITE(f);
  WRITELN(f, 'INVALID_INPUT');
  CLOSE(f);

  RESET(f);
  set_file_trap(ADR f);

  c := GREEN;
  b := TRUE;
  dummy := 123;
  p := ADR dummy;

  READ(f, c);
  READ(f, b);
  READ(f, p);

  IF c <> GREEN THEN WRITELN('FAIL: c')
  ELSE IF NOT b THEN WRITELN('FAIL: b')
  ELSE IF p <> ADR dummy THEN WRITELN('FAIL: p')
  ELSE WRITELN('trapped-preserved');
  CLOSE(f);

  { Numbers outside the type are malformed too, never stored. }
  REWRITE(f);
  WRITELN(f, '7 2 -1');
  CLOSE(f);
  RESET(f);
  set_file_trap(ADR f);
  READ(f, c);
  READ(f, b);
  IF c <> GREEN THEN WRITELN('FAIL: c range')
  ELSE IF NOT b THEN WRITELN('FAIL: b range')
  ELSE WRITELN('out-of-range-preserved');
  CLOSE(f);
END.
PAS_EOF

# Both dialects: vintage reads the enum by ordinal (pas_fread_enum_ord),
# extended by name or number (pas_fread_enum_name).
for dialect in vintage extended; do
  for opt in 0 2; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" -c "$work/trapped_read.pas" -o "$work/trapped_read.o"
    "${CC:-clang}" "$work/trapped_read.o" "$work/trap_helper.o" runtime/build/libpascalrt.a -lm -o "$work/trapped_read"
    out=$( (cd "$work" && ./trapped_read) )
    test "$out" = $'trapped-preserved\nout-of-range-preserved' ||
      die "trapped read destination preservation failed ($dialect, -O$opt): $out"
  done
done

# --- FOR control: producer per iteration; undefined after natural exit. ---
cp tests/contract/fixtures/initck_producers/for-ok.pas "$work/for-ok.pas"
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
cp tests/contract/fixtures/initck_producers/for-global.pas "$work/for-global.pas"
bin/pascal1981 --dialect extended -O0 -S "$work/for-global.pas" -o "$work/for-global.ll" 2> "$work/err"
test ! -s "$work/err"

# --- Producers through formals (routine-boundary bindings). ---
# READ into a VAR formal initializes the caller's local; READ into a value
# formal overwrites an unset transported state. FOR over a value formal is
# an ordinary producer; FOR over a VAR formal leaves the CALLER's storage
# undefined after natural termination, so the caller's checked read fails.
cp tests/contract/fixtures/initck_producers/formal-ok.pas "$work/formal-ok.pas"
expect_ok formal-ok '7z\n9\n-32768-32767\n' '7z\n9\n'
cp tests/contract/fixtures/initck_producers/formal-bad.pas "$work/formal-bad.pas"
expect_fail formal-bad '1\n2\n' 'runtime error: INITCK uninitialized local x at line 7 column 22'
echo 'PASS: INITCK scalar producers: unchecked copies, READ/READLN, FOR control, through formals'
