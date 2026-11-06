#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# The arithmetic the self-hosting compiler sources depend on.
#
# Pin the arithmetic dependencies found by the self-hosting source audit
# (docs/bootstrap_subset.md#self-hosting-arithmetic):
#   flags     the label key converter in src/ps_base.pas (CurLabelKey)
#             reduces the token value modulo 65536 and needs no MATHCK-
#             region: by the lexer's own token flags, no token of
#             ps_base.pas is unchecked
#   wide      the actual tc_expr/cg_decl units through all four stages: both
#             WORD limit constructors and the INTEGER32 build-ups use i64
#             multiply and add (plain or checked), never 16-bit arithmetic
#   labels    tests/contract/fixtures/mathck/bootstrap_labels.pas through every
#             bootstrap generation's lexer and parser (build/gen1..4), both
#             dialects: the label keys are [32767, -32768, -25536, -1]
#   pasboot   bootstrap/build/pasboot accepts and ignores MATHCK
#             (tests/unit/pasboot/mathck_ignored.pas/.out, linked with testio
#             at clang -O0..-O3 -fwrapv) and rejects malformed directives
#             with exactly `<path>:1: malformed $MATHCK`
#   native    bootstrap_labels.pas/.out under both settings (prepended), both
#             dialects, O0-O3
fixtures=tests/contract/fixtures/mathck
malformed=('MATHCK' 'MATHCK:' 'MATHCK:+' 'MATHCK+garbage')
declare -A expect=([flags]=1 [wide]=4 [labels]=8 [pasboot]=4 [malformed]=4 [native]=16)


flags_unit() {
  (cd src && "$ROOT/bin/lexer" < ps_base.pas) > "$dir/tokens.json" || die "lexer ps_base.pas"
  jq -e 'length > 1000 and all(.[]; .flags.MATHCK)' \
    "$dir/tokens.json" > /dev/null || die "unchecked tokens in ps_base.pas"
  jq -e 'any(.[]; .lexeme | ascii_upcase == "CURLABELKEY")' \
    "$dir/tokens.json" > /dev/null || die "no CurLabelKey in ps_base.pas"
  count flags
}

function_body() { # ir name: from its define line to the closing brace
  awk -v name="@$(tr '[:upper:]' '[:lower:]' <<< "$2")(" '
    !found && tolower($0) ~ /^define / && index(tolower($0), name) { found = 1 }
    found { print; if ($0 == "}") exit }' "$1"
}

wide_unit() { # unit names...
  local unit=$1 name; shift
  (cd src && "$ROOT/bin/lexer" < "$unit.pas" |
     "$ROOT/bin/parser" --dialect extended |
     "$ROOT/bin/typechecker" --dialect extended |
     "$ROOT/bin/codegen" --dialect extended) > "$dir/unit.ll" || die "stages $unit"
  for name in "$@"; do
    function_body "$dir/unit.ll" "$name" > "$dir/body.ll"
    [ -s "$dir/body.ll" ] || die "$unit: no function $name"
    # MATHCK+ compiler sources lower to checked i64 intrinsics.
    grep -qE '\b(mul i64|smul\.with\.overflow\.i64)\b' "$dir/body.ll" || die "$name: no i64 multiply"
    grep -qE '\b(add i64|sadd\.with\.overflow\.i64)\b' "$dir/body.ll" || die "$name: no i64 add"
    ! grep -qE '\b((mul|add) i16|with\.overflow\.i16)\b' "$dir/body.ll" || die "$name: 16-bit arithmetic"
    count wide
  done
}

labels_unit() { # gen1..4 lexer and parser, both dialects
  local generation dialect
  for generation in 1 2 3 4; do
    for dialect in vintage extended; do
      "build/gen$generation/lexer" < "$fixtures/bootstrap_labels.pas" |
        "build/gen$generation/parser" --dialect "$dialect" > "$dir/ast.json" ||
        die "gen$generation $dialect: lexer/parser"
      jq -e 'any(.. | objects | select(has("labels")) | .labels;
                 . == [32767, -32768, -25536, -1])' "$dir/ast.json" > /dev/null ||
        die "gen$generation $dialect: label keys"
      count labels
    done
  done
}

pasboot_unit() {
  local name opt status directive
  for name in testio mathck_ignored; do
    rm -f "$dir/$name.c"
    bootstrap/build/pasboot "tests/unit/pasboot/$name.pas" -o "$dir/$name.c" || die "pasboot $name"
  done
  for opt in 0 1 2 3; do
    rm -f "$dir/probe"
    "${CLANG:-clang}" -O"$opt" -fwrapv -w -Ibootstrap "$dir/testio.c" "$dir/mathck_ignored.c" \
      runtime/build/libpascalrt.a -o "$dir/probe" || die "clang -O$opt"
    status=0
    timeout 10 "$dir/probe" > "$dir/stdout" 2> "$dir/stderr" || status=$?
    [ "$status" -eq 0 ] || die "pasboot -O$opt: exit status $status"
    diff -u tests/unit/pasboot/mathck_ignored.out "$dir/stdout" || die "pasboot -O$opt: stdout"
    [ ! -s "$dir/stderr" ] || die "pasboot -O$opt: stderr not empty"
    count pasboot
  done
  for directive in "${malformed[@]}"; do
    printf '{$%s}\nPROGRAM Bad; BEGIN END.' "$directive" > "$dir/bad.pas"
    ! bootstrap/build/pasboot --parse-only "$dir/bad.pas" 2> "$dir/stderr" ||
      die "pasboot accepted {\$$directive}"
    printf '%s:1: malformed $MATHCK\n' "$dir/bad.pas" | diff -u - "$dir/stderr" ||
      die "pasboot {\$$directive}: stderr"
    count malformed
  done
}

native_unit() { # dialect
  local flag opt status
  for flag in + -; do
    printf '{$MATHCK%s}\n' "$flag" | cat - "$fixtures/bootstrap_labels.pas" > "$dir/labels.pas"
    for opt in 0 1 2 3; do
      rm -f "$dir/labels"
      bin/pascal1981 --dialect "$1" -O"$opt" "$dir/labels.pas" -o "$dir/labels" ||
        die "compile labels ($1 MATHCK$flag O$opt)"
      status=0
      timeout 10 "$dir/labels" > "$dir/stdout" 2> "$dir/stderr" || status=$?
      [ "$status" -eq 0 ] || die "labels $1 MATHCK$flag O$opt: exit status $status"
      diff -u "$fixtures/bootstrap_labels.out" "$dir/stdout" || die "labels $1 MATHCK$flag O$opt: stdout"
      [ ! -s "$dir/stderr" ] || die "labels $1 MATHCK$flag O$opt: stderr not empty"
      count native
    done
  done
}

# Independent units run in parallel, each in its own directory and log.
unit flags flags_unit
unit wide-tc_expr wide_unit tc_expr MaxWord16Value MaxInteger32Value
unit wide-cg_decl wide_unit cg_decl ConstIntegerType MaxConstInteger32
unit labels labels_unit
unit pasboot pasboot_unit
unit native-vintage native_unit vintage
unit native-extended native_unit extended
units_wait
echo "mathck bootstrap audit: flags, wide limit IR, ${got[labels]} generation/dialect" \
  "label-key checks, ${got[native]} native runtime cells, ${got[pasboot]} pasboot runtime" \
  "cells and malformed-directive checks passed"
