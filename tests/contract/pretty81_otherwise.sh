#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# pretty81 round-trips OTHERWISE statement lists (NEW-19): its output parses
# to the same AST, prints the same text again, and behaves the same.
require bin/pretty81 bin/lexer bin/parser bin/astcompare bin/pascal1981
src=tests/corpus/golden/case_otherwise_list.pas
expected=tests/corpus/golden/case_otherwise_list.out
ignore=()
for key in location read_location op_location meta_flags read_flags rangeck \
  indexck mathck stackck leading_comments trailing_comment; do
  ignore+=(--ignore-key "$key")
done
for dialect in vintage extended; do
  bin/lexer < "$src" | bin/parser --dialect "$dialect" > "$work/parsed.json"
  bin/pretty81 < "$work/parsed.json" > "$work/pretty.pas"
  bin/lexer < "$work/pretty.pas" | bin/parser --dialect "$dialect" \
    > "$work/reparsed.json"
  bin/astcompare "${ignore[@]}" "$work/parsed.json" "$work/reparsed.json" \
    || die "$dialect: pretty81 output parses to a different AST"
  bin/pretty81 < "$work/reparsed.json" > "$work/pretty2.pas"
  diff -u "$work/pretty.pas" "$work/pretty2.pas" \
    || die "$dialect: pretty81 output is not a fixed point"
  bin/pascal1981 --dialect "$dialect" "$work/pretty.pas" -o "$work/pretty"
  "$work/pretty" | diff -u "$expected" - \
    || die "$dialect: pretty81 output behaves differently"
done
pass 'pretty81 round-trips OTHERWISE statement lists'
