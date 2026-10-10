#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# BYWORD checks both original ordinal operands before packing their low bytes.
require bin/pascal1981 bin/lexer bin/parser bin/typechecker bin/codegen
for dialect in vintage extended; do
  specs=('INTEGER -1 -1 255' 'INTEGER 256 256 0' 'WORD 65535 65535 255')
  if [[ $dialect == extended ]]; then
    specs+=('INTEGER8 -128 -128 128' 'INTEGER32 65536 65536 0' \
      'INTEGER64 -9223372036854775807 -9223372036854775807 1' \
      'WORD32 MAXWORD32 4294967295 255' 'WORD64 MAXWORD64 18446744073709551615 255')
  fi
  for spec in "${specs[@]}"; do
    read -r kind value shown wrapped <<< "$spec"
    for operand in hi lo; do
      for flag in + -; do
        opposite=+; [[ $flag != + ]] || opposite=-
        hi=7; lo=7; [[ $operand != hi ]] || hi=selector; [[ $operand != lo ]] || lo=selector
        if [[ $operand == hi ]]; then packed=$((wrapped * 256 + 7)); else packed=$((7 * 256 + wrapped)); fi
        printf '%s\n' "PROGRAM bad; {\$INITCK-} VAR x: $kind;" "FUNCTION selector: $kind;" \
          'BEGIN WRITELN('\''arg'\''); selector := x END;' 'BEGIN' \
          "  x := $value;" '  WRITELN('\''before'\'');' "  {\$RANGECK$flag}" \
          "  WRITELN(BYWORD({\$RANGECK$opposite} $hi, $lo));" \
          '  WRITELN('\''after'\'')' 'END.' > "$work/bad.pas"
        bin/pascal1981 --dialect "$dialect" -O0 -S "$work/bad.pas" -o "$work/bad.ll"
        expected=0; [[ $flag != + ]] || expected=2
        [[ $(grep -c 'call void @pas_byword_error' "$work/bad.ll" || true) == "$expected" ]] || die "$dialect $kind $operand RANGECK$flag IR guards"
        if [[ $flag == + && $kind =~ (INTEGER|WORD)(32|64) ]]; then
          last_guard=$(grep -n 'call void @pas_byword_error' "$work/bad.ll" | tail -1 | cut -d: -f1)
          first_narrow=$(grep -nE 'trunc i(32|64) .* to i16' "$work/bad.ll" | head -1 | cut -d: -f1)
          [[ -n $first_narrow && $last_guard -lt $first_narrow ]] || die "$kind guards do not precede narrowing"
        fi
        for opt in 0 1 2 3; do
          label="$dialect $kind $operand $value RANGECK$flag O$opt"
          bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
          rc=0; { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
          printf 'before\narg\n' > "$work/expected.out"
          if [[ $flag == + ]]; then
            [[ $rc != 0 ]] || die "$label did not fail"
            printf 'runtime error: RANGECK BYWORD argument %s is outside 0..255 at line 8 column 11\n' "$shown" > "$work/expected.err"
          else
            [[ $rc == 0 ]] || die "$label failed ($rc)"
            printf '%s\nafter\n' "$packed" >> "$work/expected.out"
            : > "$work/expected.err"
          fi
          diff -u "$work/expected.out" "$work/output" || die "$label stdout"
          diff -u "$work/expected.err" "$work/error" || die "$label stderr"
          pass "$label"
        done
      done
    done
  done
  # Both arguments run once, left-to-right, before either domain check.
  printf '%s\n' 'PROGRAM order; {$INITCK-} VAR x: INTEGER; w: WORD;' \
    'FUNCTION hi: INTEGER; BEGIN WRITELN('\''hi'\''); hi := x END;' \
    'FUNCTION lo: INTEGER; BEGIN WRITELN('\''lo'\''); lo := 300 END;' \
    'BEGIN x := -1; w := 42; WRITELN('\''before'\''); w := BYWORD(hi, lo); WRITELN(w) END.' > "$work/order.pas"
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/order.pas" -o "$work/order"
    if { "$work/order" > "$work/output" 2> "$work/error"; } 2>/dev/null; then die 'bad BYWORD was published'; fi
    printf 'before\nhi\nlo\n' > "$work/expected.out"
    printf 'runtime error: RANGECK BYWORD argument -1 is outside 0..255 at line 4 column 49\n' > "$work/expected.err"
    diff -u "$work/expected.out" "$work/output"
    diff -u "$work/expected.err" "$work/error"
    pass "$dialect both evaluated once O$opt"
  done
  # CHAR/BOOLEAN use unsigned ordinals; valid high bytes must not sign-extend.
  printf '%s\n' 'PROGRAM good; {$INITCK-} TYPE E = (a,b); VAR i: INTEGER; c: CHAR; t: BOOLEAN; e: E;' \
    'BEGIN i := 0; WRITELN(BYWORD(i,i)); i := 255; WRITELN(BYWORD(i,i));' \
    ' c := CHR(255); t := TRUE; e := b; WRITELN(BYWORD(c,t)); WRITELN(BYWORD(e,c));' \
    ' IF FALSE AND THEN TRUE THEN WRITELN(BYWORD(300,-1)) END.' > "$work/good.pas"
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/good.pas" -o "$work/good"
    "$work/good" > "$work/output" 2> "$work/error"
    printf '0\n65535\n65281\n511\n' > "$work/expected.out"
    diff -u "$work/expected.out" "$work/output"
    [[ ! -s $work/error ]] || die 'valid BYWORD stderr'
    pass "$dialect ordinal boundaries/skipped call O$opt"
  done
  # Ordinary constant calls still fail when reached, independently of MATHCK.
  printf '%s\n' 'PROGRAM bad; {$MATHCK-}' 'BEGIN WRITELN('\''before'\''); WRITELN(BYWORD(7,300)); WRITELN('\''after'\'') END.' > "$work/constant-call.pas"
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/constant-call.pas" -o "$work/constant-call"
    if { "$work/constant-call" > "$work/output" 2> "$work/error"; } 2>/dev/null; then die 'bad ordinary constant call did not fail'; fi
    printf 'before\n' > "$work/expected.out"
    diff -u "$work/expected.out" "$work/output"
    grep -q '^runtime error: RANGECK BYWORD argument 300 is outside 0..255 at line 2 column ' "$work/error"
    pass "$dialect ordinary constant/MATHCK- O$opt"
  done
  # BYWORD is already admitted in CONST in both dialects. Preserve WORD type.
  for flag in + -; do
    opposite=+; [[ $flag != + ]] || opposite=-
    printf '%s\n' 'PROGRAM constants;' "{\$RANGECK$flag}" \
      "CONST C = BYWORD({\$RANGECK$opposite} 300,-1);" 'BEGIN WRITELN(C) END.' > "$work/const.pas"
    if [[ $flag == + ]]; then
      if bin/pascal1981 --dialect "$dialect" "$work/const.pas" -o "$work/const" > "$work/output" 2> "$work/error"; then die 'bad enabled CONST admitted'; fi
      grep -qxF 'RANGECK constant BYWORD argument outside 0..255 at line 3 column 11' "$work/error" || die 'CONST BYWORD diagnostic'
    else
      bin/pascal1981 --dialect "$dialect" "$work/const.pas" -o "$work/const"
      "$work/const" > "$work/output"
      printf '11519\n' > "$work/expected.out"
      diff -u "$work/expected.out" "$work/output"
    fi
    pass "$dialect CONST BYWORD RANGECK$flag snapshot"
  done
  printf '%s\n' 'PROGRAM constants; CONST C = BYWORD(255,255); D = C; T = BYWORD(TRUE,FALSE);' \
    'BEGIN WRITELN(C); WRITELN(D); WRITELN(T) END.' > "$work/const-good.pas"
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/const-good.pas" -o "$work/const-good"
    "$work/const-good" > "$work/output"
    printf '65535\n65535\n256\n' > "$work/expected.out"
    diff -u "$work/expected.out" "$work/output"
    pass "$dialect CONST WORD type/alias/boolean O$opt"
  done
done
# The two constant folders agree with runtime packing, including MIN64 and
# nested WORD-preserving wrappers (not magnitude-inferred INTEGER constants).
printf '%s\n' 'PROGRAM folds; {$INITCK-}{$RANGECK-}' \
  'CONST C = ORD(BYWORD(0,255)); D = PRED(BYWORD(1,0));' \
  'VAR x: INTEGER64; w: WORD;' 'BEGIN x := -9223372036854775807 - 1;' \
  ' WRITELN(BYWORD(-9223372036854775807 - 1,-1)); WRITELN(BYWORD(x,-1));' \
  ' WRITELN(BYWORD(300,-1) + 1); WRITELN(C); WRITELN(D); w := C; WRITELN(w + 1) END.' > "$work/folds.pas"
for opt in 0 1 2 3; do
  bin/pascal1981 --dialect extended -O"$opt" "$work/folds.pas" -o "$work/folds"
  "$work/folds" > "$work/output"
  printf '255\n255\n11520\n255\n255\n256\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  pass "constant/runtime/MIN64/wrapper twins O$opt"
done
printf '%s\n' 'PROGRAM bad; BEGIN WRITELN(BYWORD(300,0) + 1) END.' > "$work/fold-bad.pas"
if bin/pascal1981 "$work/fold-bad.pas" -o "$work/fold-bad" > "$work/output" 2> "$work/error"; then die 'enabled bad folded BYWORD admitted'; fi
grep -qxF 'RANGECK constant BYWORD argument outside 0..255 at line 1 column 28' "$work/error"
pass 'enabled folded BYWORD domain preserved'
# Elsewhere an enabled out-of-domain call is not folded: it runs with its
# runtime guard, never a codegen abort.
printf '%s\n' 'PROGRAM bad;' 'VAR a: ARRAY [0..65535] OF INTEGER;' \
  "BEGIN WRITELN('before'); WRITELN(a[ORD(BYWORD(1,300))]) END." > "$work/index-bad.pas"
bin/pascal1981 "$work/index-bad.pas" -o "$work/index-bad"
if { "$work/index-bad" > "$work/output" 2> "$work/error"; } 2>/dev/null; then die 'unfolded BYWORD index did not fail'; fi
printf 'before\n' | diff -u - "$work/output"
grep -qxF 'runtime error: RANGECK BYWORD argument 300 is outside 0..255 at line 3 column 40' "$work/error"
pass 'enabled out-of-domain BYWORD index lowered with its runtime guard'
# Parser/typechecker preserve function-name snapshots and coordinates; legacy
# calls without them inherit scoped read_flags and emit the same guard count.
(cd src; "$ROOT/bin/pascal1981" --dialect extended ../tests/contract/fixtures/byword_metadata_check.pas jsonutil.pas -o "$work/check")
printf '%s\n' 'PROGRAM policy; {$INITCK-}{$RANGECK-}' 'BEGIN' \
  ' WRITELN(BYWORD({$RANGECK+} 1,2));' ' WRITELN(BYWORD({$RANGECK-} 3,4));' \
  ' {$PUSH}{$RANGECK+} WRITELN(BYWORD(5,6));' ' {$POP} WRITELN(BYWORD(7,8)) END.' > "$work/policy.pas"
for dialect in vintage extended; do
  bin/lexer < "$work/policy.pas" | bin/parser --dialect "$dialect" > "$work/ast"
  bin/typechecker --dialect "$dialect" < "$work/ast" > "$work/typed"
  for stage in ast typed; do
    "$work/check" < "$work/$stage" > "$work/legacy"
    pass "$dialect $stage BYWORD snapshots"
  done
  for stage in typed legacy; do
    bin/codegen < "$work/$stage" > "$work/policy.ll"
    [[ $(grep -c 'call void @pas_byword_error' "$work/policy.ll") == 4 ]] || die "$dialect $stage policy guard count"
    pass "$dialect $stage scoped policy IR"
  done
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/policy.pas" -o "$work/policy"
    "$work/policy" > "$work/output"
    printf '258\n772\n1286\n1800\n' > "$work/expected.out"
    diff -u "$work/expected.out" "$work/output"
    pass "$dialect PUSH/POP/sibling policy O$opt"
  done
done
# Wide valid operands and signed low-byte packing at every supported width.
printf '%s\n' 'PROGRAM wide; {$INITCK-}{$RANGECK-} VAR i: INTEGER8; j: INTEGER32; k: INTEGER64; w: WORD8; u: WORD32; v: WORD64;' \
  'BEGIN i := -1; j := -1; k := -1; w := 255; u := 255; v := 255;' \
  ' WRITELN(BYWORD(i,w)); WRITELN(BYWORD(j,u)); WRITELN(BYWORD(k,v));' \
  ' {$RANGECK+} i := 127; j := 255; k := 255; WRITELN(BYWORD(i,w)); WRITELN(BYWORD(j,u)); WRITELN(BYWORD(k,v)) END.' > "$work/wide.pas"
for opt in 0 1 2 3; do
  bin/pascal1981 --dialect extended -O"$opt" "$work/wide.pas" -o "$work/wide"
  "$work/wide" > "$work/output"
  printf '65535\n65535\n65535\n32767\n65535\n65535\n' > "$work/expected.out"
  diff -u "$work/expected.out" "$work/output"
  pass "wide original widths O$opt"
done
# A user function named BYWORD is not the intrinsic.
printf '%s\n' 'PROGRAM shadow; FUNCTION BYWORD(x,y: INTEGER): INTEGER;' \
  'BEGIN BYWORD := x END; BEGIN WRITELN(BYWORD(300,-1)) END.' > "$work/shadow.pas"
bin/pascal1981 "$work/shadow.pas" -o "$work/shadow"
"$work/shadow" > "$work/output"
printf '300\n' > "$work/expected.out"
diff -u "$work/expected.out" "$work/output"
pass 'user BYWORD shadowing'
# CPU DEVICE shares host checks; NVPTX keeps its existing unchecked boundary.
printf '%s\n' 'DEVICE INTERFACE;' 'UNIT BWU (check);' \
  'PROCEDURE check(cell: ADS(GLOBAL) OF INTEGER);' 'END;' > "$work/bw.inc"
printf '%s\n' '(*$INCLUDE:'\''bw.inc'\''*)' 'DEVICE IMPLEMENTATION OF BWU;' \
  'PROCEDURE check(cell: ADS(GLOBAL) OF INTEGER);' 'BEGIN' \
  '  cell^ := RETYPE(INTEGER, BYWORD(cell^,0))' 'END;' '.' > "$work/bw.impl"
printf '%s\n' '(*$INCLUDE:'\''bw.inc'\''*)' 'PROGRAM cpu;' 'USES BWU (check);' \
  'TYPE P = ^INTEGER; VAR cell: P;' 'BEGIN NEW(cell); cell^ := 300; LAUNCH(check, 1, 1, cell); WRITELN('\''wrong'\'') END.' > "$work/main.pas"
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended main.pas bw.impl -o cpu)
if { "$work/cpu" > "$work/output" 2> "$work/error"; } 2>/dev/null; then die 'CPU DEVICE BYWORD did not fail'; fi
printf 'runtime error: RANGECK BYWORD argument 300 is outside 0..255 at line 5 column 28\n' > "$work/expected.err"
diff -u "$work/expected.err" "$work/error"
[[ ! -s $work/output ]] || die 'CPU DEVICE used failed BYWORD'
pass 'CPU DEVICE BYWORD failure'
(cd "$work"; "$ROOT/bin/pascal1981" --dialect extended --device-triple nvptx64-nvidia-cuda -S bw.impl -o bw.ll)
if grep -q 'pas_byword_error' "$work/bw.ll"; then die 'NVPTX emitted a host failure'; fi
pass 'NVPTX existing unchecked boundary'
finish 'RANGECK BYWORD'
