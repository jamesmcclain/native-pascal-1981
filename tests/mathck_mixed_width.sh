#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# MATHCK for operands of different integer widths, and G24 admission, from
# checked-in fixtures whose expectations come from exact integer arithmetic,
# never from compiler output. Same-family operands of different widths widen
# to the wider operand, which is the result type: the operation is checked
# (MATHCK+) or wraps (MATHCK-) at that width, never at the narrower one.
# Under tests/fixtures/mathck (extended dialect):
#   mixed_<left>_<right>_ok.pas/.out     every sampled row that fits, under
#                                        both settings (prepended), O0-O3
#   mixed_<left>_<right>_wrap.pas/.out   every sampled row that overflows,
#                                        MATHCK-, O0-O3
#   mixed_<left>_<right>_fail.pas/.expected
#                                        the first overflowing row per
#                                        operator, one per stdin case, O0/O2
#   mixed_named.pas, mixed_named_fail.pas  INTEGER32 * INTEGER at 32 bits
# The full Cartesian matrix is kept: 24 ordered same-family pairs, all
# samples, all operators. A nonconstant INTEGER-family/WORD-family mixture
# is rejected at every width pair, in either order, under either setting,
# with no IR (mixed_admission.pas/.err; docs/dialect_notes.md, G24);
# constants keep their adaptation (mixed_constants.pas/.cases).
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
signed=(INTEGER8 INTEGER INTEGER32 INTEGER64)
unsigned=(WORD8 WORD WORD32 WORD64)
declare -A symbol=([PLUS]=+ [MINUS]=- [MUL]='*' [DIV]=DIV [MOD]=MOD)
ops=(PLUS MINUS MUL DIV MOD)
declare -A expect=([ok]=192 [wrap]=96 [fail]=156 [named]=8 [admission]=340
                   [constant]=7)
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
  timeout 10 "$3" > "$dir/stdout" 2> "$dir/stderr" || status=$?
  [ "$status" -eq 0 ] || die "$1: exit status $status"
  diff -u "$2" "$dir/stdout" > /dev/null || {
    diff -u "$2" "$dir/stdout" | head -20 >&2; die "$1: stdout"; }
  [ ! -s "$dir/stderr" ] || die "$1: stderr not empty"
}

expect_fail() { # label exe expected-stdout-text expected-stderr-file
  local status=0
  # The subshell absorbs bash's own "Aborted" job report.
  (timeout 10 "$2" > "$dir/stdout" 2> "$dir/stderr"; exit) 2> /dev/null || status=$?
  [ "$status" -ne 0 ] || die "$1: did not fail"
  printf '%s' "$3" | diff -u - "$dir/stdout" || die "$1: stdout"
  diff -u "$4" "$dir/stderr" || die "$1: stderr"
}

admission_stderr() { # op symbol
  local text
  text=$(< "$fixtures/mixed_admission.err")
  printf '%s\n' "${text//'{OP}'/$1}"
}

rejected() { # label op dialect: exact G24 stderr, no published output
  admission_stderr "$2" > "$dir/expected"
  rm -f "$dir/out"
  if bin/pascal1981 --dialect "$3" -O0 "${@:4}" "$dir/reject.pas" -o "$dir/out" \
       > "$dir/stdout" 2> "$dir/stderr"; then
    die "accepted: $1"
  fi
  # Positions vary with each generated statement; locations are pinned by
  # the goldens, so compare the message without its ` at line L column C'.
  sed -E 's/ at line [0-9]+ column [0-9]+$//' "$dir/stderr" | diff -u "$dir/expected" - || die "stderr: $1"
  [ ! -s "$dir/stdout" ] || die "stdout: $1"
  [ ! -s "$dir/out" ] || die "output published: $1"
}

pair_unit() { # left-type right-type
  local base=$fixtures/mixed_${1,,}_${2,,} flag opt k status cases
  for flag in + -; do
    printf '{$MATHCK%s}\n' "$flag" | cat - "$base"_ok.pas > "$dir/ok.pas"
    for opt in 0 1 2 3; do
      build extended "$opt" "$dir/ok.pas" "$dir/ok"
      expect_run "$1 $2 ok MATHCK$flag O$opt" "$base"_ok.out "$dir/ok"
      count ok
    done
  done
  for opt in 0 1 2 3; do
    build extended "$opt" "$base"_wrap.pas "$dir/wrap"
    expect_run "$1 $2 wrap O$opt" "$base"_wrap.out "$dir/wrap"
    count wrap
  done
  mapfile -t cases < <(sed -n 's/^case //p' "$base"_fail.expected)
  [ "${#cases[@]}" -gt 0 ] || die "$base: no failure cases"
  # One overflow per operator; O0/O2 keep the run time down.
  for opt in 0 2; do
    build extended "$opt" "$base"_fail.pas "$dir/fail"
    : > "$dir/transcript"
    for k in "${cases[@]}"; do
      status=0
      (timeout 10 "$dir/fail" <<< "$k" > "$dir/stdout" 2> "$dir/stderr"; exit) \
        2> /dev/null || status=$?
      [ "$status" -eq 0 ] && status=0 || status=nonzero
      { printf 'case %s\nstatus: %s\nstdout:\n' "$k" "$status"
        cat "$dir/stdout"; echo 'stderr:'; cat "$dir/stderr"
      } >> "$dir/transcript"
      count fail
    done
    diff -u "$base"_fail.expected "$dir/transcript" || die "$1 $2 fail O$opt"
  done
}

named_unit() { # INTEGER32 * INTEGER is checked at 32 bits
  local opt
  for opt in 0 1 2 3; do
    build extended "$opt" "$fixtures/mixed_named.pas" "$dir/named"
    expect_run "named O$opt" "$fixtures/mixed_named.out" "$dir/named"
    count named
    build extended "$opt" "$fixtures/mixed_named_fail.pas" "$dir/named_fail"
    expect_fail "named fail O$opt" "$dir/named_fail" '' "$fixtures/mixed_named_fail.err"
    count named
  done
}

admission_unit() { # dialect signed-type: every unsigned partner, op, order, setting
  local dialect=$1 s=$2 u op left right flag template partners
  template=$(< "$fixtures/mixed_admission.pas")
  [ "$dialect" = vintage ] && partners=(WORD) || partners=("${unsigned[@]}")
  for u in "${partners[@]}"; do
    for op in "${ops[@]}"; do
      for left in s u; do
        [ "$left" = s ] && right=u || right=s
        for flag in + -; do
          printf '{$MATHCK%s}\n' "$flag" > "$dir/reject.pas"
          local source=${template//'{SIGNED}'/$s}
          source=${source//'{UNSIGNED}'/$u}
          printf '%s\n' "${source//'{EXPRESSION}'/$left ${symbol[$op]} $right}" \
            >> "$dir/reject.pas"
          rejected "$s/$u $left ${symbol[$op]} $right MATHCK$flag ($dialect)" \
            "${symbol[$op]}" "$dialect" -S
          count admission
        done
      done
    done
  done
}

constants_unit() {
  local template dialect flag statement want why source wide init
  template=$(< "$fixtures/mixed_constants.pas")
  while IFS='|' read -r dialect flag statement want why; do
    [[ -z $dialect || $dialect == \#* ]] && continue
    wide='' init=''
    if [ "$dialect" = extended ]; then
      wide=' a: INTEGER32; d: WORD32;' init=' a := 5; d := 5;'
    fi
    source=${template//'{WIDE}'/$wide}
    source=${source//'{INIT}'/$init}
    source=${source//'{STATEMENT}'/$statement}
    printf '{$MATHCK%s}\n%s\n' "$flag" "$source" > "$dir/reject.pas"
    [ "$(sed -n 7p "$dir/reject.pas")" = "  $statement" ] || die "line 7: $statement"
    if [[ $want == reject\ * ]]; then
      rejected "$statement" "${want#reject }" "$dialect"
    else
      build "$dialect" 0 "$dir/reject.pas" "$dir/const"
      printf '%s\n' "$want" > "$dir/expected"
      expect_run "$statement ($dialect MATHCK$flag)" "$dir/expected" "$dir/const"
    fi
    count constant
  done < "$fixtures/mixed_constants.cases"
}

# Independent units run in parallel, each in its own directory and log.
start() { # name command...
  local name=$1; shift
  dir=$work/$name
  mkdir "$dir"
  ( "$@" && touch "$dir/passed" ) > "$work/$name.log" 2>&1 &
}
for family in signed unsigned; do
  declare -n types=$family
  for left in "${types[@]}"; do
    for right in "${types[@]}"; do
      [ "$left" = "$right" ] || start "pair-$left-$right" pair_unit "$left" "$right"
    done
  done
  unset -n types
done
start named named_unit
start admission-vintage-INTEGER admission_unit vintage INTEGER
for s in "${signed[@]}"; do
  start "admission-extended-$s" admission_unit extended "$s"
done
start constants constants_unit
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
while read -r key; do got[$key]=$(( ${got[$key]:-0} + 1 )); done < <(cat "$work"/*/counts)
for key in "${!expect[@]}"; do
  [ "${got[$key]:-0}" -eq "${expect[$key]}" ] ||
    die "$key cells: ${got[$key]:-0}, expected ${expect[$key]}"
done
[ "${#got[@]}" -eq "${#expect[@]}" ] || die "unexpected cell kinds: ${!got[*]}"
echo "PASS: MATHCK mixed widths: $(( got[ok] + got[wrap] + got[fail] + got[named] ))" \
  "runtime cells (wider operand sets the checked/wrapped width, O0-O3);" \
  "${got[admission]} G24 rejections with no IR; ${got[constant]} constant-adaptation cells"
