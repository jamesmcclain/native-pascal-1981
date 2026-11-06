#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Identifiers of up to 255 characters, every one significant (NEW-17).
#
# The IBM manual (5-3) keeps only the first 31 characters of an identifier
# and limits a source line to 142 characters. Here an identifier may have up
# to 255 characters, the size of the Str255 every stage carries it in, and
# all of them are significant. A longer identifier is a located lexer
# error: it used to be cut at 255 characters, so two names sharing their
# first 255 characters silently were one variable. Checked here:
#   - 255-character names differing only in their last character stay
#     distinct as variables, constants, types, fields, enumeration members,
#     routines, parameters, labels and units, in both dialects at O0 and O2,
#     and again after pretty81, whose output prints the same twice;
#   - a 256- or 300-character identifier is rejected at its first character;
#   - typechecker diagnostics naming a 255-character identifier keep its
#     start, its distinguishing end and the location (the middle is elided;
#     they used to stop the typechecker with a RANGECK CONCAT failure), and
#     an INITCK run-time error names it whole.
require bin/pascal1981 bin/lexer bin/parser bin/pretty81

nm() { printf '%*s%s' 254 '' "$2" | tr ' ' "$1"; } # 254 x $1, then $2
A=$(nm a x) B=$(nm a y) P1=$(nm p 1) P2=$(nm p 2) F1=$(nm f 1) F2=$(nm f 2)
T1=$(nm t 1) T2=$(nm t 2) R1=$(nm r 1) R2=$(nm r 2) E1=$(nm e 1) E2=$(nm e 2)
C1=$(nm c 1) C2=$(nm c 2) L1=$(nm l 1) L2=$(nm l 2)
[[ ${#A} == 255 ]] || die 'name builder'

cat > "$work/long.pas" <<EOF
PROGRAM long(OUTPUT);
LABEL $L1, $L2;
CONST $C1 = 3; $C2 = 4;
TYPE $T1 = RECORD $R1: INTEGER; $R2: INTEGER END;
     $T2 = ($E1, $E2);
VAR $A: INTEGER; $B: INTEGER; rec: $T1; e: $T2;
FUNCTION $F1($A: INTEGER): INTEGER; BEGIN $F1 := $A + 7 END;
FUNCTION $F2: INTEGER; BEGIN $F2 := 9 END;
PROCEDURE outer;
  PROCEDURE $P1; VAR $B: INTEGER; BEGIN $B := 5; WRITELN('one ', $B) END;
  PROCEDURE $P2; BEGIN WRITELN('two') END;
BEGIN $P1; $P2 END;
BEGIN
  $A := 1; $B := 2;
  rec.$R1 := $C1; rec.$R2 := $C2;
  e := $E2;
  WRITELN($A, ' ', $B, ' ', $F1(1), ' ', $F2, ' ', rec.$R1, ' ', rec.$R2, ' ', ORD(e));
  outer;
  GOTO $L2;
  $L1: WRITELN('bad');
  $L2: WRITELN('done')
END.
EOF
printf '%s\n' '1 2 8 9 3 4 1' 'one 5' two done > "$work/long.expected"
for dialect in vintage extended; do
  for opt in 0 2; do
    if bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/long.pas" -o "$work/long" &&
       "$work/long" > "$work/stdout" && diff -u "$work/long.expected" "$work/stdout"; then
      pass "255-character identifiers stay distinct $dialect O$opt"
    else
      fail "255-character identifiers stay distinct $dialect O$opt"
    fi
  done
  bin/lexer < "$work/long.pas" | bin/parser --dialect "$dialect" > "$work/long.json"
  bin/pretty81 < "$work/long.json" > "$work/pretty.pas"
  bin/lexer < "$work/pretty.pas" | bin/parser --dialect "$dialect" > "$work/pretty.json"
  if bin/pretty81 < "$work/pretty.json" | diff -u "$work/pretty.pas" - &&
     grep -qF "$F1($A: INTEGER)" "$work/pretty.pas" &&
     bin/pascal1981 --dialect "$dialect" "$work/pretty.pas" -o "$work/pretty" &&
     "$work/pretty" > "$work/stdout" && diff -u "$work/long.expected" "$work/stdout"; then
    pass "255-character identifiers through pretty81 $dialect"
  else
    fail "255-character identifiers through pretty81 $dialect"
  fi
done

# Two units whose 255-character names differ in the last character: their
# initializers (pascal_init_<unit>, too long for a Str255) get distinct
# symbols, the same in the unit's own object and in the program's.
U1=$(nm u 1) U2=$(nm u 2)
for k in 1 2; do
  u=$(nm u "$k")
  printf '%s\n' 'INTERFACE;' "UNIT $u (get$k);" "FUNCTION get$k: INTEGER;" 'END;' > "$work/u$k.inc"
  printf '%s\n' "(*\$INCLUDE:'u$k.inc'*)" "IMPLEMENTATION OF $u;" "VAR v$k: INTEGER;" \
    "FUNCTION get$k: INTEGER; BEGIN get$k := v$k END;" "BEGIN v$k := ${k}0 END." > "$work/u$k.pas"
done
printf '%s\n' "(*\$INCLUDE:'u1.inc'*)" "(*\$INCLUDE:'u2.inc'*)" 'PROGRAM host(OUTPUT);' \
  "USES $U1 (get1);" "USES $U2 (get2);" 'BEGIN WRITELN(get1, get2) END.' > "$work/host.pas"
if (cd "$work" && "$ROOT/bin/pascal1981" host.pas u1.pas u2.pas -o host) &&
   "$work/host" > "$work/stdout" && printf '%s\n' '1020' | diff -u - "$work/stdout"; then
  pass 'units with 255-character names sharing 254'
else
  fail 'units with 255-character names sharing 254'
fi

reject() { # label source expected-stderr
  printf '%s\n' "$2" > "$work/bad.pas"
  rm -f "$work/bad"
  if bin/pascal1981 "$work/bad.pas" -o "$work/bad" > "$work/stdout" 2> "$work/stderr"; then
    fail "$1" 'accepted'
    return
  fi
  if printf '%s\n' "$3" | diff -u - "$work/stderr" && [ ! -e "$work/bad" ]; then
    pass "$1"
  else
    fail "$1" 'diagnostic'
  fi
}

# Longer identifiers are rejected, not cut: these two used to be one
# variable.
X=$(printf '%*s' 255 '' | tr ' ' b)
reject '256-character identifier' $'PROGRAM p;\nVAR '"${X}c"$': INTEGER;\nBEGIN END.' \
  'Lexer Error: identifier longer than 255 characters at line 2 column 5'
reject '300-character identifiers sharing 255' \
  $'PROGRAM p;\nVAR i: INTEGER;\n    '"${X}$(nm c 1 | cut -c1-44)"$', '"${X}$(nm c 2 | cut -c1-44)"$': INTEGER;\nBEGIN END.' \
  'Lexer Error: identifier longer than 255 characters at line 3 column 5'
# Only identifiers are lexed: a long name in a comment or a string is fine.
printf '%s\n' 'PROGRAM p(OUTPUT);' "{ ${X}${X} }" "BEGIN WRITELN('${X:0:200}') END." > "$work/ok.pas"
bin/pascal1981 "$work/ok.pas" -o "$work/ok" && "$work/ok" > "$work/stdout" &&
  printf '%s\n' "${X:0:200}" | diff -u - "$work/stdout" &&
  pass 'long text in a comment or string is no identifier' ||
  fail 'long text in a comment or string is no identifier'

# Diagnostics keep the location: the identifier's middle is elided.
elided() { # prefix name: prefix + name cut to fit with suffix $3
  local room=$((255 - ${#1} - ${#3})) head tail
  head=$(((room - 3) / 2)) tail=$((room - 3 - (room - 3) / 2))
  printf '%s%s...%s%s' "$1" "${2:0:head}" "${2: -tail}" "$3"
}
reject 'undefined 255-character identifier' $'PROGRAM p;\nBEGIN\n  '"$A"$' := 1\nEND.' \
  "Type checking failed:
$(elided 'Undefined identifier: ' "$A" ' at line 3 column 3')"
reject 'duplicate 255-character identifier' $'PROGRAM p;\nVAR '"$A"$': INTEGER;\n  '"$A"$': BOOLEAN;\nBEGIN END.' \
  "Type checking failed:
$(elided 'Identifier already declared in this scope: ' "$A" ' at line 3 column 3')"

# A run-time INITCK diagnostic is not a Str255: it names the whole identifier.
printf '%s\n' 'PROGRAM p(OUTPUT);' '{$INITCK+}' "PROCEDURE q; VAR $A: INTEGER; BEGIN WRITELN($A) END;" \
  'BEGIN q END.' > "$work/initck.pas"
bin/pascal1981 "$work/initck.pas" -o "$work/initck"
rc=0
{ "$work/initck" > "$work/stdout" 2> "$work/stderr"; } 2> /dev/null || rc=$?
if [[ $rc != 0 ]] &&
   printf 'runtime error: INITCK uninitialized local %s at line 3 column 298\n' "$A" |
     diff -u - "$work/stderr"; then
  pass 'INITCK run-time error names a 255-character local'
else
  fail 'INITCK run-time error names a 255-character local'
fi
finish 'lexer identifier limits'
