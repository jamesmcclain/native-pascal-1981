#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# pretty81 prints every STRING and LSTRING capacity (NEW-22).
#
# A literal capacity reaches pretty81 as a JSON number, which it printed as
# nothing: LSTRING(40000) came back as a bare LSTRING, a different type. A
# literal, a CONST name, a signed CONST and a WRD call, for STRING and
# LSTRING, in a VAR and a TYPE, must each print as written, parse back to
# the same AST, print the same text again and behave the same. A signed
# CONST capacity used to print as (- NN), which is no constant and did not
# parse. (+M is M in the AST.)
require bin/pretty81 bin/lexer bin/parser bin/astcompare bin/pascal1981
ignore=()
for key in location read_location op_location meta_flags read_flags rangeck \
  indexck mathck stackck leading_comments trailing_comment; do
  ignore+=(--ignore-key "$key")
done

cat > "$work/src.pas" <<'P'
PROGRAM caps(OUTPUT);
CONST N = 3; M = 5; NN = -3;
TYPE T = LSTRING(7); U = STRING(-NN);
VAR
  a: STRING(4); b: LSTRING(40000); c: STRING(N); d: LSTRING(+M);
  e: STRING(WRD(2)); f: LSTRING(WRD(N)); vt: T; vu: U;
BEGIN
  a := 'abcd'; c := 'xyz'; e := 'pq'; vu := 'uvw';
  b := 'long'; d := 'five'; f := 'ab'; vt := 'seven';
  WRITELN(UPPER(a), ' ', UPPER(b), ' ', UPPER(c), ' ', UPPER(d), ' ',
          UPPER(e), ' ', UPPER(f), ' ', UPPER(vt), ' ', UPPER(vu));
  WRITELN(a, ' ', b, ' ', c, ' ', d, ' ', e, ' ', f, ' ', vt, ' ', vu)
END.
P

for dialect in vintage extended; do
  bin/lexer < "$work/src.pas" | bin/parser --dialect "$dialect" > "$work/parsed.json"
  bin/pretty81 < "$work/parsed.json" > "$work/pretty.pas"
  missing=0
  for text in 'STRING(4)' 'LSTRING(40000)' 'STRING(N)' 'LSTRING(M)' 'STRING(WRD(2))' \
      'LSTRING(WRD(N))' 'T = LSTRING(7)' 'U = STRING(-NN)'; do
    grep -qF -- "$text" "$work/pretty.pas" || { echo "missing: $text"; missing=1; }
  done
  [[ $missing == 0 ]] && pass "capacities printed ($dialect)" || fail "capacities printed ($dialect)"
  bin/lexer < "$work/pretty.pas" | bin/parser --dialect "$dialect" > "$work/reparsed.json"
  if bin/astcompare "${ignore[@]}" "$work/parsed.json" "$work/reparsed.json" &&
     bin/pretty81 < "$work/reparsed.json" | diff -u "$work/pretty.pas" -; then
    pass "capacities round-trip ($dialect)"
  else
    fail "capacities round-trip ($dialect)"
  fi
  if bin/pascal1981 --dialect "$dialect" "$work/src.pas" -o "$work/src" &&
     bin/pascal1981 --dialect "$dialect" "$work/pretty.pas" -o "$work/pretty" &&
     diff -u <("$work/src") <("$work/pretty"); then
    pass "printed capacities behave the same ($dialect)"
  else
    fail "printed capacities behave the same ($dialect)"
  fi
done
finish 'pretty81 capacities'
