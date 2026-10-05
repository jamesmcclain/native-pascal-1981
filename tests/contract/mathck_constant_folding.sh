#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# Constant DIV/MOD folding, consumer adaptation and zero rejection.
#
# Truncating constant DIV/MOD, consumer adaptation and zero rejection, from
# checked-in fixtures whose expectations come from exact truncating
# arithmetic, never from compiler output. Under tests/contract/fixtures/mathck:
#   constfold_twins.pas/.out      each row folded as a constant and computed
#                                 at run time; both dialects, both settings
#                                 (prepended), O0-O3
#   constfold_zero.pas/.err       constant zero divisors ({EXPRESSION}):
#                                 exact stderr (one diagnostic), no output
#                                 file, O0/O2; also each statement in
#                                 zero_statements in place of the WRITELN
#   constfold_consumers.pas/.out  large constants in an index, a coercion and
#                                 a wider target (G22), both settings, O0-O3
#   constfold_ast.pas, constfold_ast_{typechecker,codegen}.err
#                                 a parsed AST with a binary CONST value
#                                 injected, fed to each folder separately
fixtures=tests/contract/fixtures/mathck
declare -A expect=([twin]=16 [zero]=128 [zero_statement]=32 [consumer]=8 [ast]=4)
# A zero divisor in an assignment, a nested expression or unspaced: still
# exactly one `Constant division by zero`.
zero_statements=('a := 5 DIV 0' 'WRITELN(7 MOD (2-2))' 'a := a DIV (3-3)'
                 'a := (4 DIV 0) + 1')
shopt -u patsub_replacement 2> /dev/null || true


expect_run() { # label dialect opt source expected-stdout
  local status=0
  rm -f "$dir/probe" # never rerun a previous cell's binary
  bin/pascal1981 --dialect "$2" -O"$3" "$4" -o "$dir/probe" || die "compile $1"
  timeout 10 "$dir/probe" > "$dir/stdout" 2> "$dir/stderr" || status=$?
  [ "$status" -eq 0 ] || die "$1: exit status $status"
  diff -u "$5" "$dir/stdout" || die "$1: stdout"
  [ ! -s "$dir/stderr" ] || die "$1: stderr not empty"
}

twins_unit() { # dialect flag
  local opt
  printf '{$MATHCK%s}\n' "$2" | cat - "$fixtures/constfold_twins.pas" > "$dir/twins.pas"
  for opt in 0 1 2 3; do
    expect_run "twins $1 MATHCK$2 O$opt" "$1" "$opt" "$dir/twins.pas" \
      "$fixtures/constfold_twins.out"
    count twin
  done
}

zero_rejected() { # kind label dialect: bad.pas fails with only the zero error
  local opt
  for opt in 0 2; do
    rm -f "$dir/bad.ll"
    if bin/pascal1981 -S --dialect "$3" -O"$opt" "$dir/bad.pas" -o "$dir/bad.ll" \
         > "$dir/stdout" 2> "$dir/stderr"; then
      die "accepted: $2 O$opt"
    fi
    # Positions vary with {EXPRESSION}; the goldens pin locations.
    sed -E 's/ at line [0-9]+ column [0-9]+$//' "$dir/stderr" | diff -u "$fixtures/constfold_zero.err" - ||
      die "stderr: $2 O$opt"
    [ ! -s "$dir/stdout" ] || die "stdout: $2 O$opt"
    [ ! -e "$dir/bad.ll" ] || die "output published: $2 O$opt"
    count "$1"
  done
}

zero_unit() { # dialect flag: every divisor form, dividend, operator, statement
  local template op dividend divisor statement
  template=$(< "$fixtures/constfold_zero.pas")
  for op in DIV MOD; do
    for dividend in 7 a; do
      for divisor in 0 Z '(2 - 2)' '(Z DIV 2)'; do
        { printf '{$MATHCK%s}\n' "$2"
          printf '%s\n' "${template//'{EXPRESSION}'/$dividend $op $divisor}"
        } > "$dir/bad.pas"
        grep -qF "WRITELN($dividend $op $divisor)" "$dir/bad.pas" || die "template"
        zero_rejected zero "$dividend $op $divisor ($1 MATHCK$2)" "$1"
      done
    done
  done
  for statement in "${zero_statements[@]}"; do
    { printf '{$MATHCK%s}\n' "$2"
      printf '%s\n' "${template//'WRITELN({EXPRESSION})'/$statement}"
    } > "$dir/bad.pas"
    grep -qF "a := 7; $statement END." "$dir/bad.pas" || die "template: $statement"
    zero_rejected zero_statement "$statement ($1 MATHCK$2)" "$1"
  done
}

consumers_unit() { # flag
  local opt
  printf '{$MATHCK%s}\n' "$1" | cat - "$fixtures/constfold_consumers.pas" > "$dir/consumers.pas"
  for opt in 0 1 2 3; do
    expect_run "consumers MATHCK$1 O$opt" extended "$opt" "$dir/consumers.pas" \
      "$fixtures/constfold_consumers.out"
    count consumer
  done
}

# Replace the probe's single CONST value with -7 $op $right. The node
# discriminator key comes from the parser's own IntLiteral, not assumed.
inject='
def isdecl: type == "object" and any(.[]; . == "ConstDecl");
([.. | select(isdecl)]
 | if length == 1 then .[0] else error("ConstDecl count \(length)") end
 | .value | to_entries | map(select(.value == "IntLiteral"))
 | if length == 1 then .[0].key else error("no IntLiteral discriminator") end) as $d
| (.. | select(isdecl) | .value) |=
  {($d): "BinOp", op: $op,
   left: {($d): "IntLiteral", value: -7},
   right: {($d): "IntLiteral", value: $right}}'

ast_unit() { # each folder on its own: DIV/MOD by 2 folds, by 0 is rejected
  local op right folded other stage
  bin/lexer < "$fixtures/constfold_ast.pas" > "$dir/tokens.json" || die "lexer"
  bin/parser --dialect extended < "$dir/tokens.json" > "$dir/ast.json" || die "parser"
  for row in 'DIV 2 -3 -1' 'MOD 2 -1 -3' 'DIV 0' 'MOD 0'; do
    read -r op right folded other <<< "$row"
    jq -c --arg op "$op" --argjson right "$right" "$inject" "$dir/ast.json" \
      > "$dir/injected.json" || die "inject $op $right"
    for stage in typechecker codegen; do
      if "bin/$stage" --dialect extended < "$dir/injected.json" \
           > "$dir/$stage.out" 2> "$dir/$stage.err"; then
        [ "$right" != 0 ] || die "$stage accepted -7 $op 0"
        [ ! -s "$dir/$stage.err" ] || die "$stage -7 $op $right: stderr not empty"
      else
        [ "$right" = 0 ] || { cat "$dir/$stage.err" >&2; die "$stage rejected -7 $op $right"; }
        # Typechecker diagnostics carry the injected node's location; the
        # goldens pin locations, so compare the message only.
        sed -E 's/ at line [0-9]+ column [0-9]+$//' "$dir/$stage.err" | diff -u "$fixtures/constfold_ast_$stage.err" - ||
          die "$stage -7 $op 0: stderr"
        [ ! -s "$dir/$stage.out" ] || die "$stage -7 $op 0: stdout not empty"
      fi
    done
    if [ "$right" != 0 ]; then
      # The folded value reaches the IR; the other operator's result does not.
      grep -qE "i16 $folded([^0-9]|\$)" "$dir/codegen.out" || die "codegen -7 $op 2: no i16 $folded"
      ! grep -qE "i16 $other([^0-9]|\$)" "$dir/codegen.out" || die "codegen -7 $op 2: i16 $other"
      ! grep -qF poison "$dir/codegen.out" || die "codegen -7 $op 2: poison"
    fi
    count ast
  done
}

# Independent units run in parallel, each in its own directory and log.
for dialect in vintage extended; do
  for flag in + -; do
    unit "twins-$dialect$flag" twins_unit "$dialect" "$flag"
    unit "zero-$dialect$flag" zero_unit "$dialect" "$flag"
  done
done
unit consumers+ consumers_unit +
unit consumers- consumers_unit -
unit ast ast_unit
units_wait
echo "PASS: constant DIV/MOD folding: $(( got[twin] + got[consumer] )) runtime cells," \
  "$(( got[zero] + got[zero_statement] )) zero rejections (one diagnostic each);" \
  "CONST/CASE/bounds AST consumers"
