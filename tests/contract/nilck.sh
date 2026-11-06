#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# NILCK null-only host dereferences: diagnostics, snapshots, aliases and IR ordering.

trap 'echo "FAIL: NILCK suite at line $LINENO (${kind:-} ${dialect:-} O${opt:-})" >&2; if [ -f "$work/err" ]; then tail -20 "$work/err" >&2; fi' ERR

# Invalid unchecked twins are compiled only, never executed.
for kind in read store field array with var chain result; do
  decl='p: PR'; setup='p := NIL'; extra=''; use='p^.v := 7'
  case "$kind" in
    read) use='WRITELN(p^.v)' ;;
    field) decl='h: RECORD p: PR END'; setup='h.p := NIL'; use='h.p^.v := 7' ;;
    array) decl='a: ARRAY [1..2] OF PR'; setup='a[1] := NIL'; use='a[1]^.v := 7' ;;
    with) use='WITH p^ DO v := 7' ;;
    var) extra="PROCEDURE use(VAR x: INTEGER); BEGIN WRITELN('callee'); x := 7 END;"; use='use(p^.v)' ;;
    chain) setup='NEW(p); p^.next := NIL'; use='p^.next^.v := 7' ;;
    result) extra="FUNCTION get: PR; BEGIN get := NIL END;"; setup='p := get'; use='WRITELN(p^.v)' ;;
  esac
  cat > "$work/$kind.pas" <<PAS
PROGRAM probe;
{\$INITCK-}{\$NILCK-}
TYPE PR = ^Rec; Rec = RECORD v: INTEGER; next: PR END;
VAR $decl;
$extra
BEGIN
  $setup;
  WRITE('prefix');
  {\$NILCK+} $use;
  WRITELN('after')
END.
PAS
  # Coordinates are the failing (last) ^ on the consumer line.
  column=$(awk 'NR == 9 { for (i=1;i<=length;i++) if (substr($0,i,1)=="^") c=i; print c }' "$work/$kind.pas")
  printf 'runtime error: NILCK NIL pointer dereference at line 9 column %s\n' "$column" > "$work/expected-err"
  printf 'prefix' > "$work/expected"
  for dialect in vintage extended; do
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/$kind.pas" -o "$work/probe" 2> "$work/err"
      test ! -s "$work/err"
      status=0
      { "$work/probe" > "$work/out" 2> "$work/err"; } 2>/dev/null || status=$?
      test "$status" -ne 0
      diff -u "$work/expected" "$work/out"
      diff -u "$work/expected-err" "$work/err"
    done
  done
  sed 's/{\$NILCK+}/{$NILCK-}/g' "$work/$kind.pas" > "$work/off.pas"
  bin/pascal1981 -O0 -S "$work/off.pas" -o "$work/off.ll"
  ! grep -q 'pas_nilck_error\|nilck\.' "$work/off.ll"
done

# NEW/copy/compare, formals/results, selected aliases, stack/foreign pointers,
# multiple dereferences and a side-effecting index evaluated exactly once.
cat > "$work/valid.pas" <<'PAS'
PROGRAM valid;
{$INITCK-}
TYPE PR = ^Rec; Rec = RECORD v: INTEGER; next: PR END;
VAR p,q: PR; a: ARRAY [1..2] OF PR; calls: INTEGER; r: Rec;
PROCEDURE setv(VAR x: INTEGER); BEGIN x := 8 END;
FUNCTION ident(x: PR): PR; BEGIN ident := x END;
FUNCTION idx: INTEGER; BEGIN calls := calls + 1; idx := 1 END;
BEGIN
  calls := 0; NEW(p); NEW(q); p^.next := q; p^.v := 1;
  a[1] := p; setv(a[idx]^.v); WITH p^.next^ DO v := 9;
  q := ident(p); IF q = p THEN WRITELN(q^.v);
  WRITELN(p^.next^.v); WRITELN(calls);
  q := ADR r; q^.v := 10; WRITELN(r.v);
  q := NIL; IF q = NIL THEN WRITELN('nil');
  DISPOSE(p^.next); DISPOSE(p)
END.
PAS
printf '8\n9\n1\n10\nnil\n' > "$work/expected"
for setting in + -; do
  sed "s/{\$INITCK-}/{\$INITCK-}{\$NILCK$setting}/" "$work/valid.pas" > "$work/twin.pas"
  for dialect in vintage extended; do
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/twin.pas" -o "$work/valid"
      "$work/valid" > "$work/out" 2> "$work/err"
      diff -u "$work/expected" "$work/out"
      test ! -s "$work/err"
    done
  done
done

# Local uninitialized pointer: INITCK must fail first, even with NILCK off.
cat > "$work/init.pas" <<'PAS'
PROGRAM init;
{$INITCK+}{$NILCK+}
PROCEDURE probe;
VAR p: ^INTEGER;
BEGIN
  WRITE('prefix'); p^ := 7
END;
BEGIN probe END.
PAS
printf 'prefix' > "$work/expected"
printf 'runtime error: INITCK uninitialized local p at line 6 column 21\n' > "$work/expected-err"
for setting in + -; do
  sed "s/{\$NILCK+}/{\$NILCK$setting}/" "$work/init.pas" > "$work/init-twin.pas"
  for opt in 0 2; do
    bin/pascal1981 -O"$opt" "$work/init-twin.pas" -o "$work/init"
    status=0
    { "$work/init" > "$work/out" 2> "$work/err"; } 2>/dev/null || status=$?
    test "$status" -ne 0
    diff -u "$work/expected" "$work/out"
    diff -u "$work/expected-err" "$work/err"
  done
done
bin/pascal1981 -O0 -S "$work/init.pas" -o "$work/init.ll"
# The guard must precede all pointee operations and heap-shadow lookup.
python3 - "$work/init.ll" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
s = s[s.index('define void @probe'):]
init = s.index('call void @pas_initck_error')
load = re.search(r'load ptr, ptr', s).start()
nil = s.index('icmp eq ptr')
fail = s.index('call void @pas_nilck_error')
heap = s.index('call ptr @pas_initck_heap_at')
store = s.index('store i16 7')
if not init < load < nil < fail < heap < store:
    raise SystemExit('incorrect INITCK/load/NILCK/heap/store ordering')
PY

# Consume flags at ^, not the root, and retain them through typechecking.
cat > "$work/flags.pas" <<'PAS'
PROGRAM flags;
{$INITCK-}
VAR p: ^INTEGER;
BEGIN
  p := NIL;
  {$NILCK-} p {$NILCK+} ^ := 1;
  {$NILCK+} p {$NILCK-} ^ := 2;
  {$PUSH}{$NILCK+} p^ := 3; {$POP} p^ := 4;
  {$NILCK=1} p^ := 5;
  {$DEBUG-} p^ := 6;
  {$DEBUG+}{$INITCK-} p^ := 7
END.
PAS
bin/pascal1981 -O0 -S "$work/flags.pas" -o "$work/flags.ll"
python3 - "$work/flags.pas" "$work/flags.ll" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
expected = [(n, lines[n-1].index('^') + 1) for n in (6, 8, 9, 11)]
actual = [tuple(map(int, m)) for m in re.findall(
    r'call void @pas_nilck_error\(i32 (\d+), i32 (\d+)\)', open(sys.argv[2]).read())]
if actual != expected:
    raise SystemExit(f'wrong consuming-token snapshots: {actual} != {expected}')
PY

# Legacy/malformed snapshots opt out; true snapshot without location uses 0:0.
bin/lexer < "$work/store.pas" | bin/parser | bin/typechecker > "$work/typed.json"
for mode in missing malformed location; do
  python3 - "$work/typed.json" "$work/legacy.json" "$mode" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1]))
def walk(x):
    if isinstance(x, dict):
        if x.get('kind') == 'DEREF':
            if sys.argv[3] == 'missing': x.pop('read_flags', None)
            elif sys.argv[3] == 'malformed': x['read_flags'] = {'NILCK': 'true'}
            else: x.pop('read_location', None)
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
walk(obj)
json.dump(obj, open(sys.argv[2], 'w'))
PY
  bin/codegen < "$work/legacy.json" > "$work/legacy.ll"
  if [ "$mode" = location ]; then
    grep -q 'call void @pas_nilck_error(i32 0, i32 0)' "$work/legacy.ll"
  else
    ! grep -q 'pas_nilck_error' "$work/legacy.ll"
  fi
done

# Enabled ordinary DEVICE dereferences reject before publishing IR.
cat > "$work/device.pas" <<'PAS'
DEVICE MODULE nildevice;
{$INITCK-}{$MATHCK-}{$NILCK+}
PROCEDURE probe(p: ^INTEGER);
BEGIN p^ := 1 END;
.
PAS
for target in cpu nvptx; do
  opts=(); if [ "$target" = nvptx ]; then opts=(--device-triple nvptx64-nvidia-cuda); fi
  if bin/pascal1981 --dialect extended "${opts[@]}" -S "$work/device.pas" -o "$work/device.ll" 2> "$work/err"; then
    echo 'FAIL: enabled DEVICE dereference accepted' >&2; exit 1
  fi
  grep -q '^NILCK unsupported boundary: DEVICE pointer dereference at line 4 column 8$' "$work/err"
  test ! -s "$work/device.ll"
  sed 's/{\$NILCK+}/{$NILCK-}/' "$work/device.pas" > "$work/device-off.pas"
  bin/pascal1981 --dialect extended "${opts[@]}" -S "$work/device-off.pas" -o "$work/device-off.ll"
  ! grep -q 'pas_nilck_error' "$work/device-off.ll"
done
echo 'PASS: NILCK null-only dereferences, diagnostics, snapshots, aliases and guard ordering'
