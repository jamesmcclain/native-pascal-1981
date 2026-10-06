#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# RANGECK CASE misses fail once, preserving snapshots, OTHERWISE and target boundaries.
require bin/pascal1981 bin/codegen

# Generate small programs so every CASE policy has both an IR and runtime oracle.
for dialect in vintage extended; do
  for shape in dynamic constant empty; do
    for flag in + -; do
      printf '%s\n' 'PROGRAM miss;' 'VAR calls: INTEGER;' \
        'FUNCTION selector: INTEGER;' 'BEGIN calls := calls + 1; WRITELN(calls); selector := 2 END;' \
        'BEGIN' '  calls := 0;' "  {\$RANGECK$flag}" > "$work/miss.pas"
      case $shape in
        dynamic) printf '%s\n' '  CASE selector OF 1: WRITELN('\''wrong'\'') END;' >> "$work/miss.pas" ;;
        constant) printf '%s\n' '  CASE 2 OF 1: WRITELN('\''wrong'\'') END;' >> "$work/miss.pas" ;;
        empty) printf '%s\n' '  CASE selector OF END;' >> "$work/miss.pas" ;;
      esac
      printf '%s\n' '  WRITELN('\''after'\'')' 'END.' >> "$work/miss.pas"
      bin/pascal1981 --dialect "$dialect" -O0 -S "$work/miss.pas" -o "$work/miss.ll"
      guards=$(grep -c 'call void @pas_case_error' "$work/miss.ll" || true)
      if [[ $flag == + ]]; then expected=1; else expected=0; fi
      [[ $guards == "$expected" ]] || die "$dialect $shape RANGECK$flag IR: $guards guards, expected $expected"
      for opt in 0 1 2 3; do
        label="$dialect $shape RANGECK$flag O$opt"
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/miss.pas" -o "$work/miss"
        rc=0
        { "$work/miss" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        : > "$work/expected.out"
        if [[ $shape != constant ]]; then printf '1\n' > "$work/expected.out"; fi
        if [[ $flag == + ]]; then
          [[ $rc != 0 ]] || die "$label did not fail"
          printf 'runtime error: RANGECK CASE selector 2 has no matching label at line 8 column 3\n' > "$work/expected.err"
        else
          [[ $rc == 0 ]] || die "$label failed ($rc)"
          printf 'after\n' >> "$work/expected.out"
          : > "$work/expected.err"
        fi
        diff -u "$work/expected.out" "$work/output" || die "$label stdout"
        diff -u "$work/expected.err" "$work/error" || die "$label stderr"
        pass "$label"
      done
    done
  done
  # CASE policy belongs to CASE, not its labels/body/END; tested both ways.
  printf '%s\n' 'PROGRAM legal;' 'VAR calls: INTEGER;' \
    'FUNCTION selector: INTEGER;' 'BEGIN calls := calls + 1; selector := 2 END;' \
    'BEGIN' '  calls := 0;' \
    '  {$RANGECK+} CASE selector OF 2: WRITELN('\''match'\'') {$RANGECK-} END;' \
    '  {$RANGECK+} CASE selector OF 1: WRITELN('\''wrong'\''); OTHERWISE WRITELN('\''other'\'') END;' \
    '  {$RANGECK-} CASE selector OF 1: WRITELN('\''wrong'\'') {$RANGECK+} END;' \
    '  IF FALSE THEN CASE selector OF END;' '  WRITELN(calls)' 'END.' > "$work/legal.pas"
  printf 'match\nother\n3\n' > "$work/expected.out"
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/legal.pas" -o "$work/legal"
    "$work/legal" > "$work/output" 2> "$work/error"
    diff -u "$work/expected.out" "$work/output" || die "$dialect legal O$opt stdout"
    [[ ! -s $work/error ]] || die "$dialect legal O$opt stderr"
    pass "$dialect legal/snapshots O$opt"
  done
  # A directive after the selector token cannot disable an enabled CASE.
  printf '%s\n' 'PROGRAM flip;' 'BEGIN' \
    '  {$RANGECK+} CASE 2 OF {$RANGECK-} 1: WRITELN('\''wrong'\'') END' 'END.' > "$work/flip.pas"
  bin/pascal1981 --dialect "$dialect" -S "$work/flip.pas" -o "$work/flip.ll"
  [[ $(grep -c 'call void @pas_case_error' "$work/flip.ll") == 1 ]] || die "$dialect CASE snapshot lost"
  pass "$dialect enabled CASE/disabled body IR"
done

# Diagnostic transport must preserve signedness and every selector bit.
for spec in 'INTEGER -32768' 'WORD 65535' 'INTEGER64 -9223372036854775807' 'WORD64 MAXWORD64'; do
  read -r kind value <<< "$spec"
  shown=$value
  [[ $value != MAXWORD64 ]] || shown=18446744073709551615
  printf '%s\n' "PROGRAM wide; VAR x: $kind;" 'BEGIN' \
    "  x := $value;" '  CASE x OF 0: WRITELN('\''wrong'\'') END' 'END.' > "$work/wide.pas"
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect extended -O"$opt" "$work/wide.pas" -o "$work/wide"
    if { "$work/wide" > "$work/output" 2> "$work/error"; } 2>/dev/null; then die "$kind O$opt did not fail"; fi
    printf 'runtime error: RANGECK CASE selector %s has no matching label at line 4 column 3\n' "$shown" > "$work/expected.err"
    diff -u "$work/expected.err" "$work/error" || die "$kind O$opt diagnostic"
    [[ ! -s $work/output ]] || die "$kind O$opt used a failed selector"
    pass "$kind O$opt diagnostic"
  done
done

# CPU DEVICE retains the host failure path; NVPTX retains its exclusion.
printf '%s\n' 'DEVICE INTERFACE;' 'UNIT CASEU (check);' \
  'PROCEDURE check(cell: ADS(GLOBAL) OF INTEGER);' 'END;' > "$work/case.inc"
printf '%s\n' '(*$INCLUDE:'\''case.inc'\''*)' 'DEVICE IMPLEMENTATION OF CASEU;' \
  'PROCEDURE check(cell: ADS(GLOBAL) OF INTEGER);' 'BEGIN' \
  '  CASE cell^ OF 1: cell^ := 3 END' 'END;' '.' > "$work/case.impl"
printf '%s\n' '(*$INCLUDE:'\''case.inc'\''*)' 'PROGRAM cpu;' 'USES CASEU (check);' \
  'TYPE P = ^INTEGER; VAR cell: P;' 'BEGIN NEW(cell); cell^ := 2; LAUNCH(check, 1, 1, cell); WRITELN('\''wrong'\'') END.' > "$work/main.pas"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended main.pas case.impl -o cpu)
if { "$work/cpu" > "$work/output" 2> "$work/error"; } 2>/dev/null; then die 'CPU DEVICE CASE did not fail'; fi
printf 'runtime error: RANGECK CASE selector 2 has no matching label at line 5 column 3\n' > "$work/expected.err"
diff -u "$work/expected.err" "$work/error" || die 'CPU DEVICE diagnostic'
[[ ! -s $work/output ]] || die 'CPU DEVICE used a failed selector'
pass 'CPU DEVICE CASE failure'
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended --device-triple nvptx64-nvidia-cuda -S case.impl -o case.ll)
if grep -q 'pas_case_error' "$work/case.ll"; then die 'NVPTX emitted a host failure'; fi
pass 'NVPTX existing unchecked boundary'
finish 'RANGECK CASE'
