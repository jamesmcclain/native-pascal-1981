#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# The typechecker and codegen constant folders agree on every shadowed name.
#
# A differential matrix (MTH-A-15). Each program under
# tests/contract/fixtures/const_fold_shadowing declares, on its first line,
# `{ probes: pN=fold|dynamic ... }`: every probe is a global INTEGER32 pN
# assigned once from an INTEGER expression `pN := E op k` whose E reaches a
# name through some scope (a CONST hidden by a VAR, parameter, FOR variable,
# WITH field or routine; an enum member; a predeclared maximum; a user
# routine spelled like ORD, CHR, SUCC, PRED, ABS, SQR, BYWORD, HIBYTE or
# LOBYTE). The two folders are observed independently:
#   typechecker  the assignment's BinOp carries resolved_type (tc_expr.pas
#                CheckFoldedOperation tags exactly the operations its
#                FoldConstInt folds);
#   codegen      the -O0 IR stores a literal into @pN (CoerceForAssign
#                materializes an INTEGER32 target from IsIntLiteralLike).
# A probe bN is a global INTEGER8 assigned once from a bare INTEGER name or
# call, `bN := E`, and is always `fold`: the typechecker accepts that
# narrowing only for an expression its FoldConstInt folds
# (CheckExprForSetTarget), and codegen must then store a literal i8 into
# @bN, which it does only when its own IsIntLiteralLike folds E.
# Both must equal the declared answer, and the program's output (each
# value worked out by hand from the scope rules, never from compiler
# output) must equal NAME.out at O0 and O2. NAME.err programs must be
# rejected with exactly that stderr.
fixtures=tests/contract/fixtures/const_fold_shadowing
require bin/pascal1981 bin/lexer bin/parser bin/typechecker bin/codegen

tc_folds() { # typed.json probe -> true|false
  jq -r --arg v "$2" '[.. | objects
      | select(.__node_type__? == "AssignStmt")
      | select((.target.name // "" | ascii_downcase) == $v)
      | (.expr | has("resolved_type"))] | if length == 1 then .[0] else "missing" end' "$1"
}

cg_folds() { # file.ll probe -> true|false
  local width=i32
  case $2 in b*) width=i8 ;; esac
  if grep -Eq "^  store $width -?[0-9]+, ptr @$2(,|$)" "$1"; then echo true; else echo false; fi
}

check_program() { # NAME
  local name=$1 src=$fixtures/$1.pas spec probe want tc cg opt status
  spec=$(sed -n '1s/^{ probes: \(.*\) }$/\1/p' "$src")
  [ -n "$spec" ] || die "$name: no probes line"
  bin/lexer < "$src" | bin/parser --dialect extended |
    bin/typechecker --dialect extended > "$dir/typed.json" || die "$name: typechecker"
  bin/pascal1981 --dialect extended -O0 -S "$src" -o "$dir/out.ll" || die "$name: codegen"
  for probe in $spec; do
    want=${probe#*=}
    probe=${probe%%=*}
    case $want in fold) want=true ;; dynamic) want=false ;; *) die "$name: bad probe $probe" ;; esac
    case $probe in
      b*) tc=true ;; # the typechecker accepted the INTEGER8 narrowing
      *) tc=$(tc_folds "$dir/typed.json" "$probe") ;;
    esac
    cg=$(cg_folds "$dir/out.ll" "$probe")
    [ "$tc" = "$cg" ] || die "$name $probe: typechecker folds=$tc, codegen folds=$cg"
    [ "$tc" = "$want" ] || die "$name $probe: both fold=$tc, expected $want"
    count probe
  done
  for opt in 0 2; do
    rm -f "$dir/prog"
    bin/pascal1981 --dialect extended -O"$opt" "$src" -o "$dir/prog" || die "$name O$opt: compile"
    status=0
    timeout 10 "$dir/prog" > "$dir/stdout" 2> "$dir/stderr" || status=$?
    [ "$status" -eq 0 ] || die "$name O$opt: exit $status"
    diff -u "$fixtures/$name.out" "$dir/stdout" || die "$name O$opt: stdout"
    [ ! -s "$dir/stderr" ] || die "$name O$opt: stderr"
    count run
  done
}

check_rejected() { # NAME
  local name=$1 src=$fixtures/$1.pas
  rm -f "$dir/out.ll"
  if bin/pascal1981 --dialect extended -S "$src" -o "$dir/out.ll" > "$dir/stdout" 2> "$dir/stderr"; then
    die "$name: accepted"
  fi
  diff -u "$fixtures/$name.err" "$dir/stderr" || die "$name: stderr"
  [ ! -e "$dir/out.ll" ] || die "$name: wrote IR"
  count reject
}

declare -A expect=()
for src in "$fixtures"/*.pas; do
  name=$(basename "$src" .pas)
  if [ -e "$fixtures/$name.err" ]; then
    expect[reject]=$((${expect[reject]:-0} + 1))
    unit "$name" check_rejected "$name"
  else
    n=$(sed -n '1s/^{ probes: \(.*\) }$/\1/p' "$src" | wc -w)
    expect[probe]=$((${expect[probe]:-0} + n))
    expect[run]=$((${expect[run]:-0} + 2))
    unit "$name" check_program "$name"
  fi
done
units_wait

# The compiler's own `wide > MAXWORD' bound test (cg_types CheckedIndexBound)
# was miscompiled as always FALSE until MAXWORD folded; the limits are now
# explicit: vintage bounds stop at 65535, extended ones at the INTEGER32
# maximum.
bound_cell() { # dialect high expected-status
  printf 'PROGRAM b;\nVAR a: ARRAY [0..%s] OF CHAR;\nBEGIN a[0] := %s; WRITELN(a[0]) END.\n' \
    "$2" "'x'" > "$work/bound.pas"
  if bin/pascal1981 --dialect "$1" -S "$work/bound.pas" -o "$work/bound.ll" 2> "$work/bound.err"; then
    [ "$3" = ok ] || die "$1 bound $2 accepted"
  else
    [ "$3" = reject ] || die "$1 bound $2 rejected: $(cat "$work/bound.err")"
    grep -qxF 'codegen: array index bound is outside -32768..65535' "$work/bound.err" ||
      die "$1 bound $2 diagnostic"
  fi
}
bound_cell vintage 65535 ok
bound_cell vintage 65536 reject
bound_cell extended 4194303 ok
echo "const_fold_shadowing: ${got[probe]:-0} probes, ${got[run]:-0} runs," \
  "${got[reject]:-0} rejections"
