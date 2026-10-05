#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# MATHCK scalar arithmetic from checked-in fixtures whose expectations come
# from exact integer arithmetic (results and wraps in fixture comments), never
# from compiler output. Families are tests/fixtures/mathck/scalar_<type>_*:
#   _ok.pas/.out          fits: MATHCK+ and MATHCK- (prepended), O0-O3
#   _wrap.pas/.out        overflows wrap under MATHCK-, O0-O3. Also the IR
#                         input: its -S -O0 IR, and codegen of its MATHCK+
#                         typed AST with the snapshots stripped (a legacy AST,
#                         linked at O0-O3), use plain arithmetic
#   _fail.pas/.expected   one trap per stdin case number; the transcript holds
#                         status, stdout and the exact located diagnostic
# scalar_constants.pas/.cases: constant operands (rejects without IR, exact
# values, partially constant traps, including operations on enumeration
# constants, which are checked at run time). twin_arith.pas/.out: never
# overflows, so it prints the same under both settings.
# Runtime failure is checked as nonzero, not a signal number or exit status
# (docs/dialect_notes.md#mathck-runtime-diagnostics).
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
# Explicit units and totals: every count below must match exactly.
declare -A widths=([integer8]=8 [integer]=16 [integer32]=32 [integer64]=64
                   [word8]=8 [word]=16 [word32]=32 [word64]=64)
units=(vintage:integer vintage:word)
for family in integer8 integer integer32 integer64 word8 word word32 word64; do
  units+=("extended:$family")
done
declare -A expect=([ok]=80 [wrap]=40 [fail]=260 [ir]=10 [snapshot]=10
                   [legacy]=40 [twin]=16 [reject]=50 [value]=168 [partial]=112)
shopt -u patsub_replacement 2> /dev/null || true

die() { echo "FAIL: $*" >&2; exit 1; }
count() { echo "$1" >> "$dir/counts"; }

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

plain_ir() { # label ir width: defined wrapping, nothing that assumes no overflow
  local absent op
  for absent in with.overflow pas_math_overflow poison undef; do
    ! grep -qF "$absent" "$2" || die "$1: $absent"
  done
  ! grep -Eq '= (add|sub|mul) (nsw|nuw)' "$2" || die "$1: nsw/nuw"
  for op in add sub mul; do
    grep -Eq "= $op i$3 " "$2" || die "$1: no $op i$3"
  done
}

both_settings() { # label dialect source expected-stdout
  local flag opt
  for flag in + -; do
    printf '{$MATHCK%s}\n' "$flag" | cat - "$3" > "$dir/both.pas"
    for opt in 0 1 2 3; do
      build "$2" "$opt" "$dir/both.pas" "$dir/both"
      expect_run "$1 $2 MATHCK$flag O$opt" "$4" "$dir/both"
    done
  done
}

family_unit() { # dialect family
  local dialect=$1 family=$2 base=$fixtures/scalar_$2 width=${widths[$2]}
  local opt k status cases
  both_settings "$family ok" "$dialect" "$base"_ok.pas "$base"_ok.out
  count 'ok 8'
  mapfile -t cases < <(sed -n 's/^case //p' "$base"_fail.expected)
  [ "${#cases[@]}" -gt 0 ] || die "$base: no failure cases"
  for opt in 0 1 2 3; do
    build "$dialect" "$opt" "$base"_wrap.pas "$dir/wrap"
    expect_run "$family wrap $dialect O$opt" "$base"_wrap.out "$dir/wrap"
    count 'wrap 1'
    build "$dialect" "$opt" "$base"_fail.pas "$dir/fail"
    : > "$dir/transcript"
    for k in "${cases[@]}"; do
      status=0
      # The subshell absorbs bash's own "Aborted" job report.
      (timeout 5 "$dir/fail" <<< "$k" > "$dir/stdout" 2> "$dir/stderr"; exit) \
        2> /dev/null || status=$?
      [ "$status" -eq 0 ] && status=0 || status=nonzero
      { printf 'case %s\nstatus: %s\nstdout:\n' "$k" "$status"
        cat "$dir/stdout"; echo 'stderr:'; cat "$dir/stderr"
      } >> "$dir/transcript"
      count 'fail 1'
    done
    diff -u "$base"_fail.expected "$dir/transcript" ||
      die "$family fail $dialect O$opt"
  done
  rm -f "$dir/wrap.ll"
  bin/pascal1981 --dialect "$dialect" -O0 -S "$base"_wrap.pas -o "$dir/wrap.ll" ||
    die "compile -S $base"_wrap.pas
  plain_ir "$family MATHCK- IR $dialect" "$dir/wrap.ll" "$width"
  count 'ir 1'
  # The same rows under MATHCK+ carry snapshots and get checked IR; with
  # mathck/op_location stripped everywhere the AST is a legacy AST, which
  # must wrap like MATHCK-, never inherit the enabled source default.
  sed '1s/^{\$MATHCK-}$/{$MATHCK+}/' "$base"_wrap.pas > "$dir/checked.pas"
  [ "$(head -n 1 "$dir/checked.pas")" = '{$MATHCK+}' ] || die "$base: directive"
  bin/lexer < "$dir/checked.pas" | bin/parser --dialect "$dialect" |
    bin/typechecker --dialect "$dialect" > "$dir/typed.json" ||
    die "$family typed AST $dialect"
  grep -Eq '"mathck":[[:space:]]*true' "$dir/typed.json" || die "$family: no snapshot"
  bin/codegen --dialect "$dialect" < "$dir/typed.json" > "$dir/checked.ll" ||
    die "$family codegen $dialect"
  grep -qF with.overflow "$dir/checked.ll" || die "$family: snapshot IR unchecked"
  count 'snapshot 1'
  jq 'walk(if type == "object" then del(.mathck, .op_location) else . end)' \
    "$dir/typed.json" > "$dir/legacy.json"
  jq -e '[.. | objects | select(has("mathck") or has("op_location"))] == []' \
    "$dir/legacy.json" > /dev/null || die "$family: snapshots left"
  bin/codegen --dialect "$dialect" < "$dir/legacy.json" > "$dir/legacy.ll" ||
    die "$family legacy codegen $dialect"
  plain_ir "$family legacy IR $dialect" "$dir/legacy.ll" "$width"
  for opt in 0 1 2 3; do
    rm -f "$dir/legacy"
    clang -O"$opt" -Wno-override-module "$dir/legacy.ll" \
      runtime/build/libpascalrt.a -lcjson -lm -o "$dir/legacy" ||
      die "$family legacy link O$opt"
    expect_run "$family legacy $dialect O$opt" "$base"_wrap.out "$dir/legacy"
    count 'legacy 1'
  done
}

twin_unit() {
  local dialect
  for dialect in vintage extended; do
    both_settings twin "$dialect" "$fixtures/twin_arith.pas" "$fixtures/twin_arith.out"
    count 'twin 8'
  done
}

constants_unit() { # dialect
  local dialect=$1 template wide='' kind scope statement expected extra
  local source flag opt status
  template=$(< "$fixtures/scalar_constants.pas")
  [ "$dialect" = extended ] && wide=' b: INTEGER8; j: INTEGER32; g: INTEGER64;'
  template=${template//'{WIDE}'/$wide}
  while IFS='|' read -r kind scope statement expected extra; do
    [[ -z $kind || $kind == \#* ]] && continue
    [[ $scope == both || $scope == "$dialect" ]] || continue
    source=${template//'{STATEMENT}'/$statement}
    for flag in + -; do
      printf '{$MATHCK%s}\n%s\n' "$flag" "$source" > "$dir/const.pas"
      [ "$(sed -n 7p "$dir/const.pas")" = "  $statement" ] || die "line 7: $statement"
      case $kind in
        reject)
          rm -f "$dir/const.ll"
          if bin/pascal1981 --dialect "$dialect" -S "$dir/const.pas" \
               -o "$dir/const.ll" > "$dir/stdout" 2> "$dir/stderr"; then
            die "accepted ($dialect MATHCK$flag): $statement"
          fi
          # Generated statements move; the goldens pin locations, so
          # compare the message without its ` at line L column C'.
          printf 'Type checking failed:\n%s\n' \
            "$expected" | diff -u - <(sed -E 's/ at line [0-9]+ column [0-9]+$//' "$dir/stderr") ||
            die "reject stderr ($dialect MATHCK$flag): $statement"
          [ ! -s "$dir/stdout" ] || die "reject stdout: $statement"
          [ ! -s "$dir/const.ll" ] || die "IR published: $statement"
          count 'reject 1' ;;
        value)
          printf '%s\n' "$expected" > "$dir/expected"
          for opt in 0 1 2 3; do
            build "$dialect" "$opt" "$dir/const.pas" "$dir/const"
            expect_run "$statement ($dialect MATHCK$flag O$opt)" "$dir/expected" "$dir/const"
            count 'value 1'
          done ;;
        partial)
          for opt in 0 1 2 3; do
            build "$dialect" "$opt" "$dir/const.pas" "$dir/const"
            if [ "$flag" = - ]; then
              printf '%s\n' "$extra" > "$dir/expected"
              expect_run "$statement ($dialect MATHCK- O$opt)" "$dir/expected" "$dir/const"
            else
              status=0
              (timeout 5 "$dir/const" > "$dir/stdout" 2> "$dir/stderr"; exit) \
                2> /dev/null || status=$?
              [ "$status" -ne 0 ] || die "partial did not trap ($dialect O$opt)"
              [ ! -s "$dir/stdout" ] || die "partial stdout ($dialect O$opt)"
              printf '%s\n' "$expected" | diff -u - "$dir/stderr" ||
                die "partial stderr ($dialect O$opt)"
            fi
            count 'partial 1'
          done ;;
        *) die "unknown kind $kind" ;;
      esac
    done
  done < "$fixtures/scalar_constants.cases"
}

# Independent units run in parallel, each in its own directory and log.
start() { # name command...
  local name=$1; shift
  dir=$work/$name
  mkdir "$dir"
  ( "$@" && touch "$dir/passed" ) > "$work/$name.log" 2>&1 &
}
for unit in "${units[@]}"; do
  start "${unit/:/-}" family_unit "${unit%%:*}" "${unit#*:}"
done
start twin twin_unit
start constants-vintage constants_unit vintage
start constants-extended constants_unit extended
wait
failed=0
for log in "$work"/*.log; do
  name=$(basename "$log" .log)
  if [ ! -e "$work/$name/passed" ]; then
    echo "FAIL: unit $name" >&2; cat "$log" >&2; failed=1
  fi
done
[ "$failed" -eq 0 ] || exit 1
declare -A got=()
while read -r key n; do
  got[$key]=$(( ${got[$key]:-0} + n ))
done < <(cat "$work"/*/counts)
for key in "${!expect[@]}"; do
  [ "${got[$key]:-0}" -eq "${expect[$key]}" ] ||
    die "$key cells: ${got[$key]:-0}, expected ${expect[$key]}"
done
[ "${#got[@]}" -eq "${#expect[@]}" ] || die "unexpected cell kinds: ${!got[*]}"
echo "PASS: MATHCK scalar fixtures, 8 types/10 width-dialect units, O0-O3:" \
  "${got[ok]} fit, ${got[wrap]} wrap, ${got[fail]} trap cells;" \
  "${got[ir]} MATHCK- IR, ${got[snapshot]} snapshot and ${got[legacy]} legacy-AST" \
  "wrap cells; ${got[twin]} twin cells; constants: ${got[reject]} rejected" \
  "without IR, ${got[value]} exact, ${got[partial]} partially constant"
