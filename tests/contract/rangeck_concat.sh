#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# CONCAT checks the wide combined length before copying or publishing it.
# Invalid unchecked copies are inspected as IR only, never executed.
require bin/pascal1981 bin/parser bin/codegen runtime/build/libpascalrt.a
cc=${CC:-clang}
text200=$(printf '%200s' '' | tr ' ' a)
text55=$(printf '%55s' '' | tr ' ' b)
for dialect in vintage extended; do
  for flag in + -; do
    opposite=+; [[ $flag != + ]] || opposite=-
    printf '%s\n' 'PROGRAM good;' 'VAR t: LSTRING(8); big: LSTRING(255); z: LSTRING(0); fixed: STRING(4);' \
      '  calls: INTEGER;' 'FUNCTION source: LSTRING(4);' \
      'BEGIN calls := calls + 1; source := '\''xy'\'' END;' 'BEGIN' \
      '  calls := 0; t := '\''ab'\''; z := '\'''\'';' "  {\$RANGECK$flag}" \
      '  CONCAT(z, '\'''\''); CONCAT(t, '\'''\''); CONCAT(t, t);' \
      "  CONCAT(t, {\$RANGECK$opposite} source);" "  {\$RANGECK$flag}" \
      '  CONCAT(t, '\''zz'\''); WRITELN(t); WRITELN(calls);' \
      '  fixed := '\''pqrs'\''; t := '\''ab'\''; CONCAT(t, fixed); WRITELN(t);' \
      "  big := '$text200'; CONCAT(big, '$text55'); WRITELN(big);" \
      '  IF FALSE THEN CONCAT(t, '\''overflow'\'')' 'END.' > "$work/good.pas"
    printf 'ababxyzz\n1\nabpqrs\n%s%s\n' "$text200" "$text55" > "$work/expected.out"
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/good.pas" -o "$work/good"
      "$work/good" > "$work/output" 2> "$work/error"
      diff -u "$work/expected.out" "$work/output"
      [[ ! -s $work/error ]] || die "$dialect legal CONCAT$flag O$opt stderr"
      pass "$dialect legal CONCAT$flag O$opt: empty, self, exact capacity, once-only source, skipped overflow"
    done
  done
  # Capacity+1, a larger overflow, and the byte boundary even when storage
  # is declared bigger (including bare LSTRING's default capacity 256).
  for spec in '0 0 2 2 0' '3 2 2 4 3' '3 2 4 6 3' '255 254 2 256 255' '255 255 2 257 255' '256 255 2 257 255' 'bare 255 2 257 255'; do
    read -r cap initial appended length limit <<< "$spec"
    kind="LSTRING($cap)"; [[ $cap != bare ]] || kind=LSTRING
    prefix=$(printf '%*s' "$initial" '' | tr ' ' a)
    setup="  t := '$prefix';"
    setup_guards=0
    if [[ $initial -gt 253 ]]; then
      remainder=$(printf '%*s' "$((initial - 200))" '' | tr ' ' b)
      setup="  t := '$text200'; CONCAT(t, '$remainder');"
      setup_guards=1
    fi
    suffix=$(printf '%*s' "$appended" '' | tr ' ' b)
    for flag in + -; do
      opposite=+; [[ $flag != + ]] || opposite=-
      printf '%s\n' 'PROGRAM bad;' "VAR t: $kind;" 'BEGIN' \
        "$setup" '  WRITELN('\''before'\'');' "  {\$RANGECK$flag}" \
        "  CONCAT(t, {\$RANGECK$opposite} '$suffix');" '  WRITELN('\''wrong'\'')' 'END.' > "$work/bad.pas"
      bin/pascal1981 --dialect "$dialect" -O0 -S "$work/bad.pas" -o "$work/bad.ll"
      expected=$setup_guards; [[ $flag != + ]] || expected=$((expected + 1))
      [[ $(grep -c 'call void @pas_concat_error' "$work/bad.ll" || true) == "$expected" ]] || die "$dialect capacity $cap CONCAT$flag IR guards"
      if [[ $flag == - ]]; then
        pass "$dialect capacity $cap disabled guard-free IR (not executed)"
        continue
      fi
      # Failure blocks must not read/copy/store destination data; the length
      # check uses i64 and its success block precedes the character copy.
      python3 tests/contract/fixtures/concat_guard_order.py "$work/bad.ll"
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
        rc=0
        { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        [[ $rc == 134 ]] || die "$dialect capacity $cap CONCAT O$opt exit $rc"
        printf 'before\n' > "$work/expected.out"
        printf 'runtime error: RANGECK CONCAT length %s exceeds capacity %s at line 7 column 3\n' "$length" "$limit" > "$work/expected.err"
        diff -u "$work/expected.out" "$work/output"
        diff -u "$work/expected.err" "$work/error"
        pass "$dialect capacity $cap checked overflow O$opt"
      done
    done
  done
done
# Observe destination preservation on failure, including all payload bytes,
# through test-only abort wrapping. The source function runs exactly once.
bin/pascal1981 --dialect extended -O0 -S tests/contract/fixtures/concat_publication.pas -o "$work/publication.ll"
for opt in 0 1 2 3; do
  "$cc" -O"$opt" "$work/publication.ll" tests/contract/fixtures/concat_publication.c \
    runtime/build/libpascalrt.a -Wl,--wrap=abort -o "$work/publication"
  rc=0
  "$work/publication" > "$work/output" 2> "$work/error" || rc=$?
  [[ $rc == 134 ]] || die "CONCAT publication O$opt exit $rc"
  printf 'PASS: CONCAT destination unchanged; source evaluated once\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  grep -qxF 'runtime error: RANGECK CONCAT length 4 exceeds capacity 3 at line 15 column 3' "$work/error"
  pass "CONCAT failed publication and once-only source O$opt"
done
# Nested and sibling statements must restore first-token RANGECK snapshots.
printf '%s\n' 'PROGRAM snapshots; VAR t: LSTRING(3);' 'BEGIN t := '\''ab'\'';' \
  '  {$RANGECK+}' '  IF TRUE THEN BEGIN {$RANGECK-} CONCAT(t, '\''xy'\'') END;' \
  '  {$RANGECK+}' '  CONCAT(t, {$RANGECK-} '\''xy'\'');' \
  '  CONCAT(t, {$RANGECK+} '\''xy'\'')' 'END.' > "$work/snapshots.pas"
bin/pascal1981 -O0 -S "$work/snapshots.pas" -o "$work/snapshots.ll"
[[ $(grep -c 'call void @pas_concat_error' "$work/snapshots.ll") == 1 ]] || die 'CONCAT nested/sibling snapshots'
pass 'CONCAT nested/sibling first-token snapshots (invalid copies not executed)'
# Legacy metadata inherits the root's enabled policy and uses 0/0 location.
printf '%s\n' 'PROGRAM legacy; VAR t: LSTRING(3);' \
  'BEGIN t := '\''ab'\''; CONCAT(t, '\''xy'\'') END.' > "$work/legacy.pas"
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
grep -qE 'call void @pas_concat_error\(i64 [^,]+, i32 3, i32 0, i32 0\)' "$work/legacy.ll" || die 'legacy CONCAT policy/location'
pass 'legacy CONCAT enabled inheritance and 0/0 location'
# CPU DEVICE uses host checks; NVPTX keeps the existing unchecked boundary.
printf '%s\n' 'DEVICE INTERFACE;' 'UNIT CONCATU (check);' \
  'PROCEDURE check;' 'END;' > "$work/concat.inc"
printf '%s\n' '(*$INCLUDE:'\''concat.inc'\''*)' 'DEVICE IMPLEMENTATION OF CONCATU;' \
  'PROCEDURE check;' 'VAR t: LSTRING(3);' 'BEGIN t := '\''ab'\''; CONCAT(t, '\''xy'\'') END;' '.' > "$work/concat.impl"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended -O0 -S concat.impl -o cpu.ll)
grep -q 'call void @pas_concat_error' "$work/cpu.ll" || die 'CPU DEVICE CONCAT guard missing'
pass 'CPU DEVICE CONCAT guard'
printf '%s\n' '(*$INCLUDE:'\''concat.inc'\''*)' 'PROGRAM cpu;' 'USES CONCATU (check);' \
  'BEGIN LAUNCH(check, 1, 1); WRITELN('\''wrong'\'') END.' > "$work/cpu.pas"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended cpu.pas concat.impl -o cpu)
rc=0
{ "$work/cpu" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
[[ $rc == 134 && ! -s $work/output ]] || die "CPU DEVICE CONCAT exit/output $rc"
grep -qxF 'runtime error: RANGECK CONCAT length 4 exceeds capacity 3 at line 5 column 18' "$work/error"
pass 'CPU DEVICE CONCAT runtime failure'
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended --device-triple nvptx64-nvidia-cuda -S concat.impl -o gpu.ll)
if grep -q 'pas_concat_error' "$work/gpu.ll"; then die 'NVPTX emitted host CONCAT failure'; fi
pass 'NVPTX existing unchecked CONCAT boundary'
finish 'RANGECK CONCAT'
