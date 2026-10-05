#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# MATHCK and RANGECK on SUCC/PRED/ABS/SQR, and the SADDOK family.
#
# MATHCK and RANGECK on the scoped builtins SUCC/PRED/ABS/SQR, and the
# never-trapping IBM library functions SADDOK/SMULOK/UADDOK/UMULOK, from
# checked-in fixtures whose expectations come from exact integer arithmetic,
# never from compiler output. Integer-family SUCC/PRED/ABS/SQR are MATHCK
# operations at the argument's own width; CHAR, BOOLEAN, enumeration and
# subrange SUCC/PRED domains are RANGECK. Under tests/contract/fixtures/mathck:
#   builtin_<type>_ok.pas/.out          fits: MATHCK+ and MATHCK- (prepended)
#   builtin_<type>_wrap.pas/.out        overflows wrap under MATHCK-; also the
#                                       IR input (MATHCK- -S, snapshot and
#                                       legacy typed AST, linked at O0-O3)
#   builtin_<type>_fail.pas/.expected   one trap per stdin case number
#   builtin_real.pas                    REAL ABS/SQR are outside MATHCK
#   builtin_domain_*                    RANGECK domains, RANGECK-, base first
#   builtin_shadow.pas                  user Succ/Sqr are ordinary calls
#   builtin_okfn*.pas                   SADDOK family: builtin and EXTERN
#                                       forms, designators, shadowing, misuse
#   builtin_nocheck.pas                 builtins that need no MATHCK check
#   builtin_constants*                  fully constant calls fit or reject
# Every runtime cell runs at O0-O3. Runtime failure is checked as nonzero,
# not an exact status (docs/dialect_notes.md#mathck-runtime-diagnostics).
fixtures=tests/contract/fixtures/mathck
declare -A widths=([integer8]=8 [integer]=16 [integer32]=32 [integer64]=64
                   [word8]=8 [word]=16 [word32]=32 [word64]=64)
units=(vintage:integer vintage:word)
for family in integer8 integer integer32 integer64 word8 word word32 word64; do
  units+=("extended:$family")
done
declare -A expect=([ok]=80 [wrap]=40 [fail]=200 [real]=4 [domain]=16
                   [domain_fail]=88 [domain_off]=4 [domain_base]=4 [shadow]=8
                   [okfn]=32 [okfn_designators]=8 [okfn_shadow]=4 [nocheck]=8
                   [ir]=10 [snapshot]=10 [legacy]=40 [const_reject]=18
                   [const_ok]=8 [nocheck_ir]=2 [okfn_ir]=2 [okfn_reject]=14)
runtime_kinds=(ok wrap fail real domain domain_fail domain_off domain_base
               shadow okfn okfn_designators okfn_shadow nocheck)
shopt -u patsub_replacement 2> /dev/null || true


build() { # dialect opt source exe; never reuse a previous cell's binary
  rm -f "$4"
  bin/pascal1981 --dialect "$1" -O"$2" "$3" -o "$4" ||
    die "compile $3 ($1, O$2)"
}

expect_run() { # label expected-stdout exe
  local status=0
  timeout 5 "$3" > "$dir/stdout" 2> "$dir/stderr" || status=$?
  [ "$status" -eq 0 ] || die "$1: exit status $status"
  diff -u "$2" "$dir/stdout" || die "$1: stdout"
  [ ! -s "$dir/stderr" ] || die "$1: stderr not empty"
}

expect_fail() { # label exe expected-stdout-text expected-stderr-file
  local status=0
  # The subshell absorbs bash's own "Aborted" job report.
  (timeout 5 "$2" > "$dir/stdout" 2> "$dir/stderr"; exit) 2> /dev/null || status=$?
  [ "$status" -ne 0 ] || die "$1: did not fail"
  printf '%s' "$3" | diff -u - "$dir/stdout" || die "$1: stdout"
  diff -u "$4" "$dir/stderr" || die "$1: stderr"
}

runs() { # kind dialect source expected-stdout [prepended first line]
  local opt
  if [ $# -gt 4 ]; then
    printf '%s\n' "$5" | cat - "$3" > "$dir/run.pas"
  else
    cp "$3" "$dir/run.pas"
  fi
  for opt in 0 1 2 3; do
    build "$2" "$opt" "$dir/run.pas" "$dir/run"
    expect_run "$1 $3 $2 ${5:-} O$opt" "$4" "$dir/run"
    count "$1"
  done
}

rejected() { # kind label message dialect-args...: exact stderr, no executable
  local kind=$1 label=$2 message=$3; shift 3
  rm -f "$dir/reject"
  if bin/pascal1981 "$@" "$dir/reject.pas" -o "$dir/reject" \
       > "$dir/stdout" 2> "$dir/stderr"; then
    die "accepted: $label"
  fi
  # Positions vary with each generated statement; locations are pinned by
  # the goldens, so compare the message without its ` at line L column C'.
  printf 'Type checking failed:\n%s\n' \
    "$message" | diff -u - <(sed -E 's/ at line [0-9]+ column [0-9]+$//' "$dir/stderr") || die "stderr: $label"
  [ ! -s "$dir/stdout" ] || die "stdout: $label"
  [ ! -e "$dir/reject" ] || die "executable published: $label"
  count "$kind"
}

no_checks() { # label ir: defined wrapping, no overflow instrumentation
  local absent
  for absent in with.overflow pas_math_overflow poison undef; do
    ! grep -qF "$absent" "$2" || die "$1: $absent"
  done
  ! grep -Eq '= (add|sub|mul) (nsw|nuw)' "$2" || die "$1: nsw/nuw"
}

family_unit() { # dialect family
  local dialect=$1 family=$2 base=$fixtures/builtin_$2 width=${widths[$2]}
  local flag opt k status cases op
  for flag in + -; do
    runs ok "$dialect" "$base"_ok.pas "$base"_ok.out "{\$MATHCK$flag}"
  done
  mapfile -t cases < <(sed -n 's/^case //p' "$base"_fail.expected)
  [ "${#cases[@]}" -gt 0 ] || die "$base: no failure cases"
  for opt in 0 1 2 3; do
    build "$dialect" "$opt" "$base"_wrap.pas "$dir/wrap"
    expect_run "$family wrap $dialect O$opt" "$base"_wrap.out "$dir/wrap"
    count wrap
    build "$dialect" "$opt" "$base"_fail.pas "$dir/fail"
    : > "$dir/transcript"
    for k in "${cases[@]}"; do
      status=0
      (timeout 5 "$dir/fail" <<< "$k" > "$dir/stdout" 2> "$dir/stderr"; exit) \
        2> /dev/null || status=$?
      [ "$status" -eq 0 ] && status=0 || status=nonzero
      { printf 'case %s\nstatus: %s\nstdout:\n' "$k" "$status"
        cat "$dir/stdout"; echo 'stderr:'; cat "$dir/stderr"
      } >> "$dir/transcript"
      count fail
    done
    diff -u "$base"_fail.expected "$dir/transcript" ||
      die "$family fail $dialect O$opt"
  done
  # MATHCK- and legacy (snapshot-free) calls wrap with plain arithmetic;
  # MATHCK+ snapshots get the overflow intrinsic.
  rm -f "$dir/wrap.ll"
  bin/pascal1981 --dialect "$dialect" -O0 -S "$base"_wrap.pas -o "$dir/wrap.ll" ||
    die "compile -S $base"_wrap.pas
  no_checks "$family MATHCK- IR $dialect" "$dir/wrap.ll"
  for op in add sub mul; do
    grep -Eq "= $op i$width " "$dir/wrap.ll" || die "$family MATHCK- IR: no $op i$width"
  done
  count ir
  sed '1s/^{\$MATHCK-}$/{$MATHCK+}/' "$base"_wrap.pas > "$dir/checked.pas"
  [ "$(head -n 1 "$dir/checked.pas")" = '{$MATHCK+}' ] || die "$base: directive"
  bin/lexer < "$dir/checked.pas" | bin/parser --dialect "$dialect" |
    bin/typechecker --dialect "$dialect" > "$dir/typed.json" ||
    die "$family typed AST $dialect"
  bin/codegen --dialect "$dialect" < "$dir/typed.json" > "$dir/checked.ll" ||
    die "$family codegen $dialect"
  grep -qF with.overflow "$dir/checked.ll" || die "$family: snapshot IR unchecked"
  count snapshot
  jq 'walk(if type == "object" then del(.mathck, .op_location) else . end)' \
    "$dir/typed.json" > "$dir/legacy.json"
  jq -e '[.. | objects | select(has("mathck") or has("op_location"))] == []' \
    "$dir/legacy.json" > /dev/null || die "$family: snapshots left"
  bin/codegen --dialect "$dialect" < "$dir/legacy.json" > "$dir/legacy.ll" ||
    die "$family legacy codegen $dialect"
  no_checks "$family legacy IR $dialect" "$dir/legacy.ll"
  for opt in 0 1 2 3; do
    rm -f "$dir/legacy"
    clang -O"$opt" -Wno-override-module "$dir/legacy.ll" \
      runtime/build/libpascalrt.a -lcjson -lm -o "$dir/legacy" ||
      die "$family legacy link O$opt"
    expect_run "$family legacy $dialect O$opt" "$base"_wrap.out "$dir/legacy"
    count legacy
  done
}

domain_unit() { # RANGECK owns the domains under either MATHCK setting
  local flag dialect opt
  for flag in + -; do
    for dialect in vintage extended; do
      runs domain "$dialect" "$fixtures/builtin_domain_ok.pas" \
        "$fixtures/builtin_domain_ok.out" "{\$MATHCK$flag}{\$RANGECK+}"
    done
  done
  # RANGECK- leaves the domains unchecked; CHAR wraps at its byte.
  runs domain_off vintage "$fixtures/builtin_domain_off.pas" \
    "$fixtures/builtin_domain_off.out" '{$RANGECK-}'
  # A subrange at its host's extreme: MATHCK's base overflow comes first.
  for opt in 0 1 2 3; do
    build vintage "$opt" "$fixtures/builtin_domain_base.pas" "$dir/base"
    expect_fail "domain base O$opt" "$dir/base" '' "$fixtures/builtin_domain_base.err"
    count domain_base
  done
}

domain_fail_unit() { # row-number
  local statement message source flag opt
  IFS='|' read -r statement message < <(grep -v '^#' "$fixtures/builtin_domain_fail.cases" |
    sed -n "$1p")
  [ -n "$statement" ] && [ -n "$message" ] || die "domain row $1 missing"
  printf 'runtime error: %s\n' "$message" > "$dir/expected"
  source=$(< "$fixtures/builtin_domain_fail.pas")
  source=${source//'{STATEMENT}'/$statement}
  for flag in + -; do
    printf '{$MATHCK%s}{$RANGECK+}\n%s\n' "$flag" "$source" > "$dir/domain.pas"
    [ "$(sed -n 8p "$dir/domain.pas")" = "  $statement" ] || die "line 8: $statement"
    for opt in 0 1 2 3; do
      build vintage "$opt" "$dir/domain.pas" "$dir/domain"
      expect_fail "$statement MATHCK$flag O$opt" "$dir/domain" $'prefix\n' "$dir/expected"
      count domain_fail
    done
  done
}

misc_unit() { # REAL, shadowing and no-check builtins
  local dialect
  runs real vintage "$fixtures/builtin_real.pas" "$fixtures/builtin_real.out"
  for dialect in vintage extended; do
    runs shadow "$dialect" "$fixtures/builtin_shadow.pas" "$fixtures/builtin_shadow.out"
    runs nocheck "$dialect" "$fixtures/builtin_nocheck.pas" "$fixtures/builtin_nocheck.out"
    rm -f "$dir/nocheck.ll"
    bin/pascal1981 -S --dialect "$dialect" -O0 "$fixtures/builtin_nocheck.pas" \
      -o "$dir/nocheck.ll" || die "compile -S nocheck ($dialect)"
    ! grep -qF pas_math_overflow "$dir/nocheck.ll" || die "nocheck IR $dialect: overflow call"
    count nocheck_ir
  done
}

okfn_unit() { # dialect: the builtin never calls the failure; EXTERN matches it
  local dialect=$1 flag form
  for flag in + -; do
    for form in okfn okfn_extern; do
      runs okfn "$dialect" "$fixtures/builtin_$form.pas" "$fixtures/builtin_okfn.out" \
        "{\$MATHCK$flag}"
    done
  done
  runs okfn_designators "$dialect" "$fixtures/builtin_okfn_designators.pas" \
    "$fixtures/builtin_okfn_designators.out"
  [ "$dialect" = vintage ] && runs okfn_shadow vintage \
    "$fixtures/builtin_okfn_shadow.pas" "$fixtures/builtin_okfn_shadow.out"
  printf '{$MATHCK+}\n' | cat - "$fixtures/builtin_okfn.pas" > "$dir/okfn.pas"
  rm -f "$dir/okfn.ll"
  bin/pascal1981 -S --dialect "$dialect" -O0 "$dir/okfn.pas" -o "$dir/okfn.ll" ||
    die "compile -S okfn ($dialect)"
  ! grep -qF pas_math_overflow "$dir/okfn.ll" || die "okfn IR $dialect: overflow call"
  grep -qF with.overflow "$dir/okfn.ll" || die "okfn IR $dialect: no overflow intrinsic"
  ! grep -qF '@SADDOK' "$dir/okfn.ll" || die "okfn IR $dialect: library call"
  count okfn_ir
}

constants_unit() { # fully constant calls fit at compile time or reject
  local template wide dialect statement message why source flag
  template=$(< "$fixtures/builtin_constants.pas")
  while IFS='|' read -r dialect statement message why; do
    [[ -z $dialect || $dialect == \#* ]] && continue
    [ "$dialect" = extended ] && wide=' g: INTEGER64;' || wide=''
    source=${template//'{WIDE}'/$wide}
    source=${source//'{STATEMENT}'/$statement}
    for flag in + -; do
      printf '{$MATHCK%s}\n%s\n' "$flag" "$source" > "$dir/reject.pas"
      [ "$(sed -n 6p "$dir/reject.pas")" = "  $statement" ] || die "line 6: $statement"
      rejected const_reject "$statement ($dialect MATHCK$flag)" "$message" --dialect "$dialect"
    done
  done < "$fixtures/builtin_constants.cases"
  for flag in + -; do
    runs const_ok extended "$fixtures/builtin_constants_ok.pas" \
      "$fixtures/builtin_constants_ok.out" "{\$MATHCK$flag}"
  done
  template=$(< "$fixtures/builtin_okfn_reject.pas")
  while IFS='|' read -r statement message; do
    [[ -z $statement || $statement == \#* ]] && continue
    printf '%s\n' "${template//'{CALL}'/$statement}" > "$dir/reject.pas"
    grep -qF "IF $statement THEN" "$dir/reject.pas" || die "okfn reject: $statement"
    rejected okfn_reject "$statement" "$message"
  done < "$fixtures/builtin_okfn_reject.cases"
}

# Independent units run in parallel, each in its own directory and log.
for unit in "${units[@]}"; do
  unit "${unit/:/-}" family_unit "${unit%%:*}" "${unit#*:}"
done
rows=$(grep -vc '^#' "$fixtures/builtin_domain_fail.cases")
[ "$rows" -eq 11 ] || die "$rows domain failure rows, expected 11"
for row in $(seq "$rows"); do
  unit "domain-fail-$row" domain_fail_unit "$row"
done
unit domain domain_unit
unit misc misc_unit
unit okfn-vintage okfn_unit vintage
unit okfn-extended okfn_unit extended
unit constants constants_unit
units_wait
runtime=0
for key in "${runtime_kinds[@]}"; do runtime=$(( runtime + got[$key] )); done
echo "PASS: MATHCK builtins: SUCC/PRED/ABS/SQR $runtime runtime cells (all scalar" \
  "widths, both dialects/settings, RANGECK domains, O0-O3); ${got[legacy]}" \
  "legacy-AST wrap cells (${got[ir]} MATHCK- IR, ${got[snapshot]} snapshot);" \
  "$(( got[const_reject] + got[const_ok] )) constant cells; SADDOK/SMULOK/UADDOK/UMULOK" \
  "builtin and EXTERN forms, $(( got[nocheck_ir] + got[okfn_ir] + got[okfn_reject] ))" \
  "IR/rejection checks"
