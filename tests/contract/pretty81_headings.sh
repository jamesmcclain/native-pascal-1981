#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# pretty81 prints a PROGRAM heading's parameters as written (NEW-20).
#
# It used to print `(input, output)' for every program, so a heading with
# no parameters, with only OUTPUT, or with other names or spelling parsed
# back to a different AST ($.params). Each heading here must print, parse
# to the same AST and print the same text again.
require bin/pretty81 bin/lexer bin/parser bin/astcompare bin/pascal1981
ignore=()
for key in location read_location op_location meta_flags read_flags rangeck \
  indexck mathck stackck leading_comments trailing_comment; do
  ignore+=(--ignore-key "$key")
done

roundtrip() { # label dialect heading expected-heading-line
  printf '%s\n' "$3" 'BEGIN WRITELN(1) END.' > "$work/src.pas"
  if bin/lexer < "$work/src.pas" | bin/parser --dialect "$2" > "$work/parsed.json" &&
     bin/pretty81 < "$work/parsed.json" > "$work/pretty.pas" &&
     grep -qxF -- "$4" "$work/pretty.pas" &&
     bin/lexer < "$work/pretty.pas" | bin/parser --dialect "$2" > "$work/reparsed.json" &&
     bin/astcompare "${ignore[@]}" "$work/parsed.json" "$work/reparsed.json" &&
     bin/pretty81 < "$work/reparsed.json" | diff -u "$work/pretty.pas" - &&
     bin/pascal1981 --dialect "$2" "$work/src.pas" -o "$work/src" &&
     bin/pascal1981 --dialect "$2" "$work/pretty.pas" -o "$work/pretty" &&
     diff -u <("$work/src") <("$work/pretty"); then
    pass "$1 ($2)"
  else
    head -3 "$work/pretty.pas"
    fail "$1 ($2)"
  fi
}

for dialect in vintage extended; do
  roundtrip 'no parameters' "$dialect" 'PROGRAM p;' 'PROGRAM p;'
  roundtrip 'OUTPUT only' "$dialect" 'PROGRAM p(OUTPUT);' 'PROGRAM p(OUTPUT);'
  roundtrip 'INPUT and OUTPUT' "$dialect" 'PROGRAM p(INPUT, OUTPUT);' 'PROGRAM p(INPUT, OUTPUT);'
  roundtrip 'lower case' "$dialect" 'PROGRAM p(input, output);' 'PROGRAM p(input, output);'
  roundtrip 'other names' "$dialect" 'PROGRAM p(output, data, Log);' 'PROGRAM p(output, data, Log);'
done
finish 'pretty81 headings'
