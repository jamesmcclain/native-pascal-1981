#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# CHR checks original integer values at its name token, before narrowing.
require bin/pascal1981 bin/parser bin/codegen
for dialect in vintage extended; do
  specs=('INTEGER -1 -1 255' 'INTEGER 256 256 0' 'WORD 65535 65535 255')
  if [[ $dialect == extended ]]; then
    specs+=('INTEGER8 -128 -128 128' 'INTEGER32 65536 65536 0' \
      'INTEGER64 -9223372036854775807 -9223372036854775807 1' \
      'WORD32 MAXWORD32 4294967295 255' 'WORD64 MAXWORD64 18446744073709551615 255')
  fi
  for spec in "${specs[@]}"; do
    read -r kind value shown wrapped <<< "$spec"
    for flag in + -; do
      opposite=+; [[ $flag != + ]] || opposite=-
      printf '%s\n' "PROGRAM bad; VAR x: $kind;" "FUNCTION selector: $kind;" \
        'BEGIN WRITELN('\''arg'\''); selector := x END;' 'BEGIN' \
        "  x := $value;" '  WRITELN('\''before'\'');' "  {\$RANGECK$flag}" \
        "  WRITELN(ORD(CHR({\$RANGECK$opposite} selector)));" \
        '  WRITELN('\''after'\'')' 'END.' > "$work/bad.pas"
      bin/pascal1981 --dialect "$dialect" -O0 -S "$work/bad.pas" -o "$work/bad.ll"
      expected=0; [[ $flag != + ]] || expected=1
      [[ $(grep -c 'call void @pas_chr_error' "$work/bad.ll" || true) == "$expected" ]] || die "$dialect $kind $value CHR$flag IR guards"
      for opt in 0 1 2 3; do
        label="$dialect $kind $value RANGECK$flag O$opt"
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
        rc=0
        { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        printf 'before\narg\n' > "$work/expected.out"
        if [[ $flag == + ]]; then
          [[ $rc != 0 ]] || die "$label did not fail"
          printf 'runtime error: RANGECK CHR argument %s is outside 0..255 at line 8 column 15\n' "$shown" > "$work/expected.err"
        else
          [[ $rc == 0 ]] || die "$label failed ($rc)"
          printf '%s\nafter\n' "$wrapped" >> "$work/expected.out"
          : > "$work/expected.err"
        fi
        diff -u "$work/expected.out" "$work/output" || die "$label stdout"
        diff -u "$work/expected.err" "$work/error" || die "$label stderr"
        pass "$label"
      done
    done
  done
  # Ordinary constant calls, including nested calls, fail before publication.
  for value in -1 300; do
    printf '%s\n' 'PROGRAM bad;' 'BEGIN' '  WRITELN('\''before'\'');' \
      "  WRITELN(ORD(CHR($value)));" '  WRITELN('\''after'\'')' 'END.' > "$work/constant.pas"
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/constant.pas" -o "$work/constant"
      if { "$work/constant" > "$work/output" 2> "$work/error"; } 2>/dev/null; then die "$dialect constant $value O$opt did not fail"; fi
      printf 'before\n' > "$work/expected.out"
      printf 'runtime error: RANGECK CHR argument %s is outside 0..255 at line 4 column 15\n' "$value" > "$work/expected.err"
      diff -u "$work/expected.out" "$work/output"
      diff -u "$work/expected.err" "$work/error"
      pass "$dialect constant $value O$opt"
    done
  done
  printf '%s\n' 'PROGRAM good;' 'VAR x: INTEGER;' 'BEGIN' \
    '  x := 0; WRITELN(ORD(CHR(x)));' '  x := 127; WRITELN(ORD(CHR(x)));' \
    '  x := 128; WRITELN(ORD(CHR(x)));' '  x := 255; WRITELN(ORD(CHR(x)))' 'END.' > "$work/good.pas"
  printf '0\n127\n128\n255\n' > "$work/expected.out"
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/good.pas" -o "$work/good"
    "$work/good" > "$work/output" 2> "$work/error"
    diff -u "$work/expected.out" "$work/output"
    [[ ! -s $work/error ]] || die "$dialect valid O$opt stderr"
    pass "$dialect valid boundaries O$opt"
  done
done
# Eight-bit inputs need no LLVM truncation, but signed negatives still check.
printf '%s\n' 'PROGRAM bytes; VAR i: INTEGER8; w: WORD8; bad: INTEGER;' \
  'BEGIN i := 127; w := 255; bad := 300; WRITELN(ORD(CHR(i))); WRITELN(ORD(CHR(w)));' \
  '  IF FALSE AND THEN ORD(CHR(bad)) = 0 THEN WRITELN('\''wrong'\'') END.' > "$work/bytes.pas"
printf '127\n255\n' > "$work/expected.out"
for opt in 0 1 2 3; do
  bin/pascal1981 --dialect extended -O"$opt" "$work/bytes.pas" -o "$work/bytes"
  "$work/bytes" > "$work/output" 2> "$work/error"
  diff -u "$work/expected.out" "$work/output"
  [[ ! -s $work/error ]] || die "bytes/skipped CHR O$opt stderr"
  pass "eight-bit inputs and skipped CHR O$opt"
done
# CONST consumers do not generate a runtime call: reject enabled invalid CHR
# while folding, using the CHR name's policy, not the end of its argument.
for flag in + -; do
  opposite=+; [[ $flag != + ]] || opposite=-
  printf '%s\n' 'PROGRAM c;' "{\$RANGECK$flag}" \
    "CONST C = CHR({\$RANGECK$opposite} 300);" 'BEGIN WRITELN(ORD(C)) END.' > "$work/const.pas"
  if [[ $flag == + ]]; then
    if bin/pascal1981 --dialect extended "$work/const.pas" -o "$work/const" > "$work/output" 2> "$work/error"; then die 'enabled CONST CHR admitted'; fi
    grep -qF 'RANGECK constant CHR argument outside 0..255' "$work/error" || die 'CONST CHR diagnostic'
  else
    bin/pascal1981 --dialect extended "$work/const.pas" -o "$work/const"
    "$work/const" > "$work/output"
    printf '44\n' > "$work/expected.out"
    diff -u "$work/expected.out" "$work/output"
  fi
  pass "CONST CHR RANGECK$flag snapshot"
done
# User declarations named CHR are not the builtin.
printf '%s\n' 'PROGRAM shadow;' 'FUNCTION CHR(x: INTEGER): INTEGER;' \
  'BEGIN CHR := x END;' 'BEGIN WRITELN(CHR(300)) END.' > "$work/shadow.pas"
bin/pascal1981 "$work/shadow.pas" -o "$work/shadow"
"$work/shadow" > "$work/output"
printf '300\n' > "$work/expected.out"
diff -u "$work/expected.out" "$work/output"
pass 'user CHR shadowing'
# CPU DEVICE checked, NVPTX retains its existing unchecked RANGECK boundary.
printf '%s\n' 'DEVICE INTERFACE;' 'UNIT CHRU (check);' \
  'PROCEDURE check(cell: ADS(GLOBAL) OF INTEGER);' 'END;' > "$work/chr.inc"
printf '%s\n' '(*$INCLUDE:'\''chr.inc'\''*)' 'DEVICE IMPLEMENTATION OF CHRU;' \
  'PROCEDURE check(cell: ADS(GLOBAL) OF INTEGER);' 'BEGIN' \
  '  cell^ := ORD(CHR(cell^))' 'END;' '.' > "$work/chr.impl"
printf '%s\n' '(*$INCLUDE:'\''chr.inc'\''*)' 'PROGRAM cpu;' 'USES CHRU (check);' \
  'TYPE P = ^INTEGER; VAR cell: P;' 'BEGIN NEW(cell); cell^ := 300; LAUNCH(check, 1, 1, cell); WRITELN('\''wrong'\'') END.' > "$work/main.pas"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended main.pas chr.impl -o cpu)
if { "$work/cpu" > "$work/output" 2> "$work/error"; } 2>/dev/null; then die 'CPU DEVICE CHR did not fail'; fi
printf 'runtime error: RANGECK CHR argument 300 is outside 0..255 at line 5 column 16\n' > "$work/expected.err"
diff -u "$work/expected.err" "$work/error"
[[ ! -s $work/output ]] || die 'CPU DEVICE used failed CHR'
pass 'CPU DEVICE CHR failure'
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended --device-triple nvptx64-nvidia-cuda -S chr.impl -o chr.ll)
if grep -q 'pas_chr_error' "$work/chr.ll"; then die 'NVPTX emitted a host failure'; fi
pass 'NVPTX existing unchecked boundary'
finish 'RANGECK CHR'
