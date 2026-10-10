#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# SUCC/PRED preserve subrange domains through function results without replaying calls.
require bin/pascal1981
fixture=tests/contract/fixtures/rangeck_succpred_result.pas
checks=0

program() { # expression seed RANGECK MATHCK
  printf '{$RANGECK%s}{$MATHCK%s}\n' "$3" "$4" > "$work/test.pas"
  local source
  source=$(< "$fixture")
  source=${source//\{EXPR\}/$1}
  source=${source//\{SEED\}/$2}
  printf '%s\n' "$source" >> "$work/test.pas"
}

run_check() { # dialect opt expected-value [expected-error]
  rm -f "$work/test"
  bin/pascal1981 --dialect "$1" -O"$2" "$work/test.pas" -o "$work/test" || die "compile $1 O$2"
  local status=0
  (timeout 5 "$work/test" > "$work/out" 2> "$work/err"; exit) 2> /dev/null || status=$?
  if [ $# -eq 4 ]; then
    [ "$status" -ne 0 ] && [ "$status" -ne 124 ] || die "expected failure ($1 O$2)"
    printf 'prefix\ncall\n' > "$work/expected"
    printf 'runtime error: %s\n' "$4" > "$work/expected.err"
  else
    [ "$status" -eq 0 ] || die "unexpected failure ($1 O$2)"
    printf 'prefix\ncall\n%s\nend\n' "$3" > "$work/expected"
    : > "$work/expected.err"
  fi
  diff -u "$work/expected" "$work/out" || die "output: call replay or result use"
  diff -u "$work/expected.err" "$work/err" || die "diagnostic"
  checks=$((checks + 1))
}

# Direct calls with actuals, bare/explicit niladic calls and nested builtins.
for dialect in vintage extended; do
  for math in + -; do
    while IFS='|' read -r expr seed result bad; do
      for range in + -; do
        program "$expr" "$seed" "$range" "$math"
        for opt in 0 1 2 3; do
          if [ "$range" = + ]; then
            run_check "$dialect" "$opt" "$result" "value $bad is outside subrange -2..3"
          else
            run_check "$dialect" "$opt" "$result"
          fi
        done
      done
    done <<'CASES'
SUCC(GetValue(3))|3|4|4
PRED(GetValue(-2))|-2|-3|-3
SUCC(GetBare)|3|4|4
SUCC(GetBare())|3|4|4
PRED(GetBare)|-2|-3|-3
PRED(GetBare())|-2|-3|-3
SUCC(PRED(GetValue(-2)))|-2|-2|-3
PRED(SUCC(GetValue(3)))|3|3|4
CASES
    for range in + -; do
      program 'SUCC(GetValue(1))' 1 "$range" "$math"
      for opt in 0 1 2 3; do run_check "$dialect" "$opt" 2; done
    done
  done
  # Non-integer host types also retain their narrower declared domains.
  for math in + -; do
    while IFS='|' read -r declarations base initial bad lo hi; do
      printf '{$RANGECK+}{$MATHCK%s}\n' "$math" > "$work/test.pas"
      cat >> "$work/test.pas" <<OTHER
PROGRAM OtherDomain;
TYPE $declarations
VAR x: $base;
FUNCTION GetOther: Slice;
BEGIN WRITELN('call'); GetOther := x END;
BEGIN
  x := $initial;
  WRITELN('prefix');
  WRITELN(ORD(SUCC(GetOther)));
  WRITELN('end');
END.
OTHER
      for opt in 0 1 2 3; do
        run_check "$dialect" "$opt" 0 "value $bad is outside subrange $lo..$hi"
      done
    done <<'DOMAINS'
Slice = 'a'..'c';|CHAR|'c'|100|97|99
Slice = FALSE..FALSE;|BOOLEAN|FALSE|1|0|0
Color = (red, green, blue); Slice = red..green;|Color|green|2|0|1
DOMAINS
  done
  # A user SUCC/PRED is an ordinary function, even when its return type is
  # a subrange. Only the surrounding builtin step checks that domain.
  for math in + -; do
    for name in Succ Pred; do
      if [ "$name" = Succ ]; then expr='PRED(Succ(-2))'; bad=-3
      else expr='SUCC(Pred(3))'; bad=4; fi
      program "$expr" 1 + "$math"
      sed "s/GetValue/$name/g" "$work/test.pas" > "$work/shadow.pas"
      mv "$work/shadow.pas" "$work/test.pas"
      for opt in 0 1 2 3; do
        run_check "$dialect" "$opt" 0 "value $bad is outside subrange -2..3"
      done
    done
  done
  # WITH fields are real typed symbols at lowering time, so their domain
  # already follows the storage route. Pin this formerly uncertain R7 path
  # separately: no function-result store may hide a missed builtin check.
  for math in + -; do
    printf '{$RANGECK+}{$MATHCK%s}\n' "$math" > "$work/test.pas"
    cat >> "$work/test.pas" <<'WITH'
PROGRAM WithDomain;
TYPE Small = -2..3; Box = RECORD item: Small END;
VAR b: Box;
BEGIN
  b.item := 3;
  WRITELN('prefix'); WRITELN('call');
  WITH b DO WRITELN(SUCC(item));
  WRITELN('end');
END.
WITH
    for opt in 0 1 2 3; do
      run_check "$dialect" "$opt" 0 'value 4 is outside subrange -2..3'
    done
  done
  # At the shared host/domain endpoint, enabled MATHCK wins. With MATHCK
  # disabled the wrapped step still fails the subrange domain check.
  for math in + -; do
    program 'SUCC(GetTop)' 3 + "$math"
    for opt in 0 1 2 3; do
      if [ "$math" = + ]; then
        run_check "$dialect" "$opt" 0 'MATHCK signed overflow in SUCC at line 15 column 11 (operand=32767)'
      else
        run_check "$dialect" "$opt" 0 'value -32768 is outside subrange 0..32767'
      fi
    done
  done
  # Bare variable/constant bindings must not borrow a same-named routine's
  # return domain. Both SUCC operands here are ordinary INTEGER values.
  cat > "$work/test.pas" <<'BINDINGS'
{$RANGECK+}{$MATHCK+}
PROGRAM Bindings;
TYPE Small = -2..3;
FUNCTION GetBare: Small;
BEGIN WRITELN('wrong call'); GetBare := 3 END;
PROCEDURE VariableBinding;
VAR GetBare: INTEGER;
BEGIN GetBare := 10; WRITELN(SUCC(GetBare)) END;
PROCEDURE ConstantBinding;
CONST GetBare = 10;
BEGIN WRITELN(SUCC(GetBare)) END;
BEGIN
  WRITELN('prefix'); WRITELN('call');
  VariableBinding; ConstantBinding;
  WRITELN('end');
END.
BINDINGS
  for opt in 0 1 2 3; do run_check "$dialect" "$opt" $'11\n11'; done
  # IR: the additional domain guard is after the call/step, never a second
  # call; disabled twins contribute no guard. Callee return-store checks
  # are independent and must not be mistaken for the builtin's guard.
  for range in + -; do
    program 'SUCC(GetValue(3))' 3 "$range" -
    bin/pascal1981 --dialect "$dialect" -O0 -S "$work/test.pas" -o "$work/test.ll"
    [ "$(grep -c 'call i16 @GetValue' "$work/test.ll")" = 1 ] || die 'IR: call count'
    # Restrict to main: the callee itself has its own return-store check.
    awk '/^define .* @main\(/ {main=1} main {print} main && /^}/ {exit}' "$work/test.ll" > "$work/main.ll"
    guards=$(grep -c 'call void @pas_subrange_error' "$work/main.ll" || true)
    if [ "$range" = + ]; then
      [ "$guards" = 1 ] || die 'IR: enabled domain guard'
      call_line=$(grep -n 'call i16 @GetValue' "$work/main.ll" | cut -d: -f1)
      step_line=$(grep -n ' = add i16 ' "$work/main.ll" | cut -d: -f1)
      guard_line=$(grep -n 'call void @pas_subrange_error' "$work/main.ll" | cut -d: -f1)
      [ "$call_line" -lt "$step_line" ] && [ "$step_line" -lt "$guard_line" ] || die 'IR: call/step/guard order'
    else
      [ "$guards" = 0 ] || die 'IR: disabled domain guard'
    fi
    checks=$((checks + 1))
  done
done

echo "PASS: SUCC/PRED function-result domains ($checks checks)"
