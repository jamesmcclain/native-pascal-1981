#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# Scalar DIV/MOD safety from checked-in fixtures; expectations come from exact
# truncating arithmetic, never from compiler output. Under tests/fixtures/mathck:
#   divmod_<dialect>_{checked,unchecked}.pas/.out
#       {$MATHCK+}/{$MATHCK-}: runtime-built signed MIN, MIN MOD -1 = 0, the
#       truncating sign table and unsigned maximum, at every width of the
#       dialect, O0-O3. MIN DIV -1 = MIN appears only in the unchecked
#       fixture (its MATHCK+ trap belongs to mathck_scalar.sh). The same
#       sources' -S -O0 IR divides only by a sanitized `select ..., iN 1, iN`
#       defined earlier in the function, after the div.bad/div.ok branch.
#   divmod_zero.pas/.cases
#       dynamic zero divisors trap under both settings with an exact located
#       diagnostic, after evaluating each operand once.
#   divmod_device.pas
#       NVPTX rejects DEVICE DIV/MOD (located MATHCK boundary under MATHCK+,
#       mandatory-safety text under MATHCK-) with no output; host codegen of
#       the same AST keeps the guard.
# A typed AST stripped of snapshots (a legacy AST) keeps the mandatory guard
# with 0:0 coordinates. Runtime failure is checked as nonzero, not an exact
# status (docs/dialect_notes.md#mathck-runtime-diagnostics).
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
declare -A widths=([vintage]='16' [extended]='8 16 32 64')
declare -A expect=([ok]=16 [ir]=4 [zero]=160 [nvptx]=4 [host]=4 [legacy]=4)

die() { echo "FAIL: $*" >&2; exit 1; }
count() { echo "$1" >> "$dir/counts"; }

build() { # dialect opt source exe; never reuse a previous cell's binary
  rm -f "$4"
  bin/pascal1981 --dialect "$1" -O"$2" "$3" -o "$4" ||
    die "compile $3 ($1, O$2)"
}

typed_ast() { # dialect source json
  bin/lexer < "$2" | bin/parser --dialect "$1" |
    bin/typechecker --dialect "$1" > "$3" || die "typed AST $2 ($1)"
}

guarded_ir() { # label ir widths: every division takes a sanitized divisor
  local found
  found=$(awk '
    /^define / { inside = 1; split("", safe); bad = ok = 0; next }
    inside && /^}/ { inside = 0; next }
    !inside { next }
    $2 == "=" && $3 == "select" && $4 == "i1" && $7 == "1," && $6 == $8 {
      safe[$1] = $6
    }
    /label %div\.bad/ { bad = 1 }
    $2 == "=" && $3 ~ /^(sdiv|srem|udiv|urem)$/ &&
        $4 ~ /^i(8|16|32|64)$/ && $6 ~ /^%/ {
      if (safe[$6] != $4 || !bad || !ok) {
        print "unguarded: " $0 > "/dev/stderr"; exit 1
      }
      found++
    }
    /div\.ok/ { ok = 1 }
    END { print found + 0 }' "$2") || die "$1: unguarded division"
  [ "$found" -ge $(( $(wc -w <<< "$3") * 4 )) ] || die "$1: $found divisions"
  ! grep -Eq 'poison|undef' "$2" || die "$1: poison/undef"
}

success_unit() { # dialect setting
  local dialect=$1 base=$fixtures/divmod_$1_$2 opt status
  for opt in 0 1 2 3; do
    build "$dialect" "$opt" "$base".pas "$dir/ok"
    status=0
    timeout 5 "$dir/ok" > "$dir/stdout" 2> "$dir/stderr" || status=$?
    [ "$status" -eq 0 ] || die "$base O$opt: exit status $status"
    diff -u "$base".out "$dir/stdout" || die "$base O$opt: stdout"
    [ ! -s "$dir/stderr" ] || die "$base O$opt: stderr not empty"
    count 'ok 1'
  done
  rm -f "$dir/ok.ll"
  bin/pascal1981 --dialect "$dialect" -S -O0 "$base".pas -o "$dir/ok.ll" ||
    die "compile -S $base.pas"
  guarded_ir "$base IR" "$dir/ok.ll" "${widths[$dialect]}"
  count 'ir 1'
}

zero_source() { # flag type left op
  local source
  source=$(< "$fixtures/divmod_zero.pas")
  source=${source//'{TYPE}'/$2}
  source=${source//'{LEFT}'/$3}
  source=${source//'{OP}'/$4}
  printf '{$MATHCK%s}\n%s\n' "$1" "$source" > "$dir/zero.pas"
  [ "$(sed -n 9p "$dir/zero.pas")" = "  WRITELN(LeftValue $4 RightValue);" ] ||
    die "line 9: $2 $4"
}

zero_unit() { # dialect type
  local dialect=$1 scope type left op expected flag opt status rows=0
  while IFS='|' read -r scope type left op expected; do
    [[ -z $scope || $scope == \#* ]] && continue
    [[ $type == "$2" ]] && [[ $scope == both || $scope == "$dialect" ]] || continue
    rows=$((rows + 1))
    for flag in + -; do
      zero_source "$flag" "$type" "$left" "$op"
      for opt in 0 1 2 3; do
        build "$dialect" "$opt" "$dir/zero.pas" "$dir/zero"
        status=0
        # The subshell absorbs bash's own "Aborted" job report.
        (timeout 5 "$dir/zero" > "$dir/stdout" 2> "$dir/stderr"; exit) \
          2> /dev/null || status=$?
        local label="$type $op $dialect MATHCK$flag O$opt"
        [ "$status" -ne 0 ] || die "$label: did not trap"
        printf 'prefix\nleft\nright\n' | diff -u - "$dir/stdout" ||
          die "$label: stdout"
        printf '%s\n' "$expected" | diff -u - "$dir/stderr" || die "$label: stderr"
        count 'zero 1'
      done
    done
  done < "$fixtures/divmod_zero.cases"
  [ "$rows" -eq 2 ] || die "$2 ($dialect): $rows zero rows"
}

device_unit() {
  local flag op expected
  for flag in + -; do
    for op in DIV MOD; do
      { printf '{$MATHCK%s}\n' "$flag"
        sed "s/a DIV b/a $op b/" "$fixtures/divmod_device.pas"; } > "$dir/device.pas"
      grep -qF "c := a $op b" "$dir/device.pas" || die "device source: $op"
      typed_ast extended "$dir/device.pas" "$dir/device.json"
      if bin/codegen --dialect extended --emit-ptx \
           --device-triple nvptx64-nvidia-cuda < "$dir/device.json" \
           > "$dir/stdout" 2> "$dir/stderr"; then
        die "NVPTX accepted $op (MATHCK$flag)"
      fi
      # MATHCK+ reaches the located DEVICE boundary first (the operator is at
      # line 10 column 10); under MATHCK- mandatory zero safety still rejects.
      if [ "$flag" = + ]; then
        expected='MATHCK unsupported boundary: DEVICE arithmetic at line 10 column 10'
      else
        expected='codegen: scalar DIV/MOD safety is unsupported on DEVICE'
      fi
      printf '%s\n' "$expected" | diff -u - "$dir/stderr" ||
        die "NVPTX $op (MATHCK$flag): stderr"
      [ ! -s "$dir/stdout" ] || die "NVPTX $op (MATHCK$flag): output"
      count 'nvptx 1'
      bin/codegen --dialect extended < "$dir/device.json" > "$dir/host.ll" ||
        die "host codegen $op (MATHCK$flag)"
      grep -qF 'call void @pas_math_zero' "$dir/host.ll" &&
        grep -qF div.safe "$dir/host.ll" && grep -qF 'label %div.bad' "$dir/host.ll" ||
        die "host $op (MATHCK$flag): unguarded"
      count 'host 1'
    done
  done
}

legacy_unit() {
  # Codegen takes coordinates only from the operation's own snapshot; a
  # legacy typed AST without one still gets the mandatory guard at 0:0.
  local dialect json coords calls
  zero_source + INTEGER -7 DIV
  for dialect in vintage extended; do
    typed_ast "$dialect" "$dir/zero.pas" "$dir/typed.json"
    grep -qF '"op_location"' "$dir/typed.json" || die "$dialect: no op_location"
    jq 'walk(if type == "object" then del(.mathck, .op_location) else . end)' \
      "$dir/typed.json" > "$dir/legacy.json"
    ! grep -qF '"op_location"' "$dir/legacy.json" || die "$dialect: op_location left"
    for json in typed legacy; do
      [ "$json" = typed ] && coords='i32 9, i32 21)' || coords='i32 0, i32 0)'
      bin/codegen --dialect "$dialect" < "$dir/$json.json" > "$dir/$json.ll" ||
        die "$json codegen $dialect"
      calls=$(grep -F 'call void @pas_math_zero' "$dir/$json.ll" || true)
      [ "$(grep -c . <<< "$calls")" -eq 1 ] && [[ $calls == *"$coords" ]] ||
        die "$json $dialect: pas_math_zero calls: $calls"
      count 'legacy 1'
    done
  done
}

# Independent units run in parallel, each in its own directory and log.
start() { # name command...
  local name=$1; shift
  dir=$work/$name
  mkdir "$dir"
  ( "$@" && touch "$dir/passed" ) > "$work/$name.log" 2>&1 &
}
for dialect in vintage extended; do
  for setting in checked unchecked; do
    start "ok-$dialect-$setting" success_unit "$dialect" "$setting"
  done
done
for type in INTEGER WORD; do
  start "zero-vintage-$type" zero_unit vintage "$type"
done
for type in INTEGER8 INTEGER INTEGER32 INTEGER64 WORD8 WORD WORD32 WORD64; do
  start "zero-extended-$type" zero_unit extended "$type"
done
start device device_unit
start legacy legacy_unit
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
echo "PASS: scalar DIV/MOD safety, all widths, both settings, O0-O3:" \
  "${got[ok]} defined-result and ${got[zero]} zero-divisor runtime cells;" \
  "${got[ir]} guarded IR; ${got[nvptx]} NVPTX rejections, ${got[host]} host guards;" \
  "${got[legacy]} snapshot/legacy coordinate checks"
