#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# NILCK-controlled DISPOSE: null checks before retirement/free, snapshots and aliases.
trap 'echo "FAIL: DISPOSE suite at line $LINENO (${kind:-} ${dialect:-} O${opt:-})" >&2; if [ -f "$work/err" ]; then tail -20 "$work/err" >&2; fi' ERR

# NIL is valid initialized data. Disposal, not pointer transport, checks it.
for kind in plain field array selected descriptor; do
  decl='p: ^INTEGER'; setup='p := NIL'; actual='p'
  case "$kind" in
    field) decl='h: RECORD p: ^INTEGER END'; setup='h.p := NIL'; actual='h.p' ;;
    array) decl='a: ARRAY [1..2] OF ^INTEGER'; setup='a[1] := NIL'; actual='a[1]' ;;
    selected) decl='h: ^R'; setup='NEW(h); h^.p := NIL'; actual='h^.p' ;;
    descriptor) decl='p: ^Cells'; setup='p := NIL' ;;
  esac
  cat > "$work/$kind.pas" <<PAS
PROGRAM disposecheck;
{\$INITCK-}
TYPE Cells = SUPER ARRAY [1..*] OF INTEGER; R = RECORD p: ^INTEGER END;
VAR $decl;
BEGIN
  $setup;
  WRITE('prefix');
  DISPOSE($actual);
  WRITELN('after')
END.
PAS
  printf 'prefix' > "$work/expected"
  printf 'runtime error: NILCK NIL pointer passed to DISPOSE at line 8 column 3\n' > "$work/expected-err"
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
  # Unlike invalid dereferences, free(NULL) is a safe host off-twin probe.
  sed 's/{$INITCK-}/{$INITCK-}{$NILCK-}/' "$work/$kind.pas" > "$work/off.pas"
  for opt in 0 2; do
    bin/pascal1981 -O"$opt" "$work/off.pas" -o "$work/off"
    "$work/off" > "$work/out" 2> "$work/err"
    printf 'prefixafter\n' > "$work/expected-off"
    diff -u "$work/expected-off" "$work/out"
    test ! -s "$work/err"
  done
done

# Positive allocations: selected slots evaluate once; formal/result/copy,
# VAR aliases and descriptor allocations keep their existing representation.
cat > "$work/valid.pas" <<'PAS'
PROGRAM valid;
{$INITCK-}
TYPE Cells = SUPER ARRAY [-1..*] OF INTEGER; PC = ^Cells;
     PI = ^INTEGER; R = RECORD p: PI END;
VAR a: ARRAY [1..2] OF PI; h: ^R; calls: INTEGER; d,e: PC; p,q: PI;
FUNCTION idx: INTEGER; BEGIN calls := calls + 1; idx := 1 END;
FUNCTION ident(x: PI): PI; BEGIN ident := x END;
PROCEDURE release(VAR x: PI); BEGIN DISPOSE(x) END;
BEGIN
  calls := 0; NEW(a[1]); DISPOSE(a[idx]); WRITELN(calls);
  NEW(h); NEW(h^.p); DISPOSE(h^.p); DISPOSE(h);
  NEW(p); q := ident(p); release(q);
  NEW(d, 2); e := d; DISPOSE(e);
  WRITELN('done')
END.
PAS
printf '1\ndone\n' > "$work/expected"
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

# INITCK must diagnose uninitialized pointer storage before reading its bits.
for kind in plain descriptor; do
  typ='^INTEGER'; if [ "$kind" = descriptor ]; then typ='^Cells'; fi
  cat > "$work/init.pas" <<PAS
PROGRAM init;
{\$INITCK+}
TYPE Cells = SUPER ARRAY [1..*] OF INTEGER;
PROCEDURE probe;
VAR p: $typ;
BEGIN
  WRITE('prefix'); DISPOSE(p)
END;
BEGIN probe END.
PAS
  printf 'prefix' > "$work/expected"
  printf 'runtime error: INITCK uninitialized local p at line 7 column 28\n' > "$work/expected-err"
  for setting in + -; do
    sed "s/{\$INITCK+}/{\$INITCK+}{\$NILCK$setting}/" "$work/init.pas" > "$work/init-twin.pas"
    for opt in 0 2; do
      bin/pascal1981 -O"$opt" "$work/init-twin.pas" -o "$work/init"
      status=0
      { "$work/init" > "$work/out" 2> "$work/err"; } 2>/dev/null || status=$?
      test "$status" -ne 0
      diff -u "$work/expected" "$work/out"
      diff -u "$work/expected-err" "$work/err"
    done
  done
  bin/pascal1981 -O0 -S "$work/init.pas" -o "$work/init-$kind.ll"
  sed "s/  WRITE('prefix');/  p := NIL; WRITE('prefix');/" "$work/init.pas" > "$work/initialized.pas"
  column=$(awk 'NR == 7 { print index($0, "DISPOSE") }' "$work/initialized.pas")
  printf 'runtime error: NILCK NIL pointer passed to DISPOSE at line 7 column %s\n' "$column" > "$work/expected-err"
  for opt in 0 2; do
    bin/pascal1981 -O"$opt" "$work/initialized.pas" -o "$work/initialized"
    status=0
    { "$work/initialized" > "$work/out" 2> "$work/err"; } 2>/dev/null || status=$?
    test "$status" -ne 0
    diff -u "$work/expected" "$work/out"
    diff -u "$work/expected-err" "$work/err"
  done
done
python3 - "$work/init-plain.ll" "$work/init-descriptor.ll" <<'PY'
import re, sys
for path in sys.argv[1:]:
    s = open(path).read().split('define void @probe()', 1)[1].split('\n}', 1)[0]
    positions = [s.index('call void @pas_initck_error'),
                 re.search(r'load (?:ptr|\{ ptr, i64 \}), ptr', s).start(),
                 s.index('icmp eq ptr'), s.index('call void @pas_nilck_dispose_error'),
                 s.index('call void @pas_initck_heap_dispose'), s.index('call void @free')]
    if positions != sorted(positions):
        raise SystemExit('incorrect INITCK/load/NILCK/retire/free order')
    if len(re.findall(r'load (?:ptr|\{ ptr, i64 \}), ptr', s)) != 1:
        raise SystemExit('pointer evaluated more than once')
    bad = s.split('nilck.bad:', 1)[1].split('nilck.ok:', 1)[0]
    if 'unreachable' not in bad or re.search(r'\bstore\b|call void @free|call void @pas_initck_heap_dispose', bad):
        raise SystemExit('failure changes pointer/descriptor/registry or returns')
PY

# DISPOSE name owns the snapshot/location; directives in actuals do not.
cat > "$work/flags.pas" <<'PAS'
PROGRAM flags;
{$INITCK-}
VAR p: ^INTEGER;
BEGIN
  p := NIL;
  {$NILCK+} DISPOSE({$NILCK-} p);
  {$NILCK-} DISPOSE({$NILCK+} p);
  {$NILCK-}{$PUSH}{$NILCK+} DISPOSE(p); {$POP} DISPOSE(p);
  {$NILCK=1} DISPOSE(p);
  {$DEBUG-} DISPOSE(p);
  {$DEBUG+}{$INITCK-} DISPOSE(p)
END.
PAS
bin/pascal1981 -O0 -S "$work/flags.pas" -o "$work/flags.ll"
python3 - "$work/flags.pas" "$work/flags.ll" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
expected = [(n, lines[n-1].index('DISPOSE') + 1) for n in (6, 8, 9, 11)]
actual = [tuple(map(int, m)) for m in re.findall(
    r'call void @pas_nilck_dispose_error\(i32 (\d+), i32 (\d+)\)', open(sys.argv[2]).read())]
if actual != expected:
    raise SystemExit(f'wrong disposal-token snapshots: {actual} != {expected}')
PY

# Missing/malformed legacy enablement opts out; absent location is 0:0.
bin/lexer < "$work/plain.pas" | bin/parser | bin/typechecker > "$work/typed.json"
for mode in missing malformed location; do
  python3 - "$work/typed.json" "$work/legacy.json" "$mode" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1]))
def walk(x):
    if isinstance(x, dict):
        if x.get('name', '').upper() == 'DISPOSE' and x.get('__node_type__') == 'ProcCallStmt':
            if sys.argv[3] == 'missing': x.pop('meta_flags', None)
            elif sys.argv[3] == 'malformed': x['meta_flags'] = {'NILCK': 'true'}
            else: x.pop('location', None)
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
walk(obj)
json.dump(obj, open(sys.argv[2], 'w'))
PY
  bin/codegen < "$work/legacy.json" > "$work/legacy.ll"
  if [ "$mode" = location ]; then
    grep -q 'call void @pas_nilck_dispose_error(i32 0, i32 0)' "$work/legacy.ll"
  else
    ! grep -q 'pas_nilck_dispose_error' "$work/legacy.ll"
  fi
done

# Interpose retirement/free to prove null failure reaches neither. Then
# remove the IR guard (safe NULL only): the same runtime oracle must catch it.
cat > "$work/hooks.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
void __wrap_pas_initck_heap_dispose(void *p) {
    (void)p; fflush(stdout); fputs("unexpected retirement\n", stderr); fflush(stderr); _Exit(91);
}
void __wrap_free(void *p) {
    (void)p; fflush(stdout); fputs("unexpected free\n", stderr); fflush(stderr); _Exit(92);
}
C
bin/pascal1981 -O0 -S "$work/plain.pas" -o "$work/plain.ll"
python3 - "$work/plain.ll" "$work/mutant.ll" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
s, n = re.subn(r'br i1 %nilck\.isnil, label %nilck\.bad, label %nilck\.ok',
               'br label %nilck.ok', s)
if n != 1:
    raise SystemExit(f'guard removal mutation not applied exactly once: {n}')
open(sys.argv[2], 'w').write(s)
PY
printf 'prefix' > "$work/expected"
for variant in plain mutant; do
  "${CC:-clang}" "$work/$variant.ll" "$work/hooks.c" runtime/build/libpascalrt.a \
    -Wl,--wrap=pas_initck_heap_dispose,--wrap=free -lm -o "$work/hooked"
  status=0
  { "$work/hooked" > "$work/out" 2> "$work/err"; } 2>/dev/null || status=$?
  test "$status" -ne 0
  diff -u "$work/expected" "$work/out"
  if [ "$variant" = plain ]; then
    printf 'runtime error: NILCK NIL pointer passed to DISPOSE at line 8 column 3\n' > "$work/expected-err"
  else
    test "$status" -eq 91
    printf 'unexpected retirement\n' > "$work/expected-err"
  fi
  diff -u "$work/expected-err" "$work/err"
done

# A user routine named DISPOSE is not the builtin or a pointer consumer.
cat > "$work/shadow.pas" <<'PAS'
PROGRAM shadow;
PROCEDURE DISPOSE(x: INTEGER); BEGIN WRITELN(x) END;
BEGIN DISPOSE(7) END.
PAS
bin/pascal1981 "$work/shadow.pas" -o "$work/shadow"
"$work/shadow" > "$work/out" 2> "$work/err"
printf '7\n' > "$work/expected"
diff -u "$work/expected" "$work/out"
test ! -s "$work/err"
echo 'PASS: NILCK DISPOSE null guards, name-token snapshots, INITCK precedence and once-only retirement/free'
