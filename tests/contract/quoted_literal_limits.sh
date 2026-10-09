#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
require bin/pascal1981 bin/lexer
# Quoted token spellings include both delimiters and doubled quotes. Until
# the AST/token transport grows past Str255, reject instead of truncating.
for dialect in vintage extended; do
  for n in 252 253 254 255 256 300 1000; do
    text=$(printf '%*s' "$n" '' | tr ' ' x)
    printf "PROGRAM p; BEGIN WRITELN('%s') END.\n" "$text" > "$work/literal.pas"
    if [[ $n -le 253 ]]; then
      for opt in 0 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/literal.pas" -o "$work/literal"
        "$work/literal" > "$work/output"
        printf '%s\n' "$text" > "$work/expected"
        diff -u "$work/expected" "$work/output"
        pass "$dialect quoted payload $n O$opt preserved"
      done
    else
      if bin/pascal1981 --dialect "$dialect" "$work/literal.pas" -o "$work/literal" > "$work/output" 2> "$work/error"; then
        die "$dialect quoted payload $n silently admitted"
      fi
      grep -qxF 'Lexer Error: quoted literal exceeds 255-byte token limit' "$work/error"
      [[ ! -s $work/output ]] || die 'rejected literal wrote output'
      pass "$dialect quoted payload $n explicitly rejected"
    fi
  done
  for n in 126 127; do
    text=$(printf '%*s' "$n" '' | tr ' ' "'")
    spelling=$(printf '%s' "$text" | sed "s/'/''/g")
    printf "PROGRAM p; BEGIN WRITELN('%s') END.\n" "$spelling" > "$work/quotes.pas"
    if [[ $n == 126 ]]; then
      bin/pascal1981 --dialect "$dialect" "$work/quotes.pas" -o "$work/quotes"
      "$work/quotes" > "$work/output"
      printf '%s\n' "$text" > "$work/expected"
      diff -u "$work/expected" "$work/output"
      pass "$dialect doubled quotes preserved at spelling boundary"
    else
      if bin/pascal1981 --dialect "$dialect" "$work/quotes.pas" -o "$work/quotes" > "$work/output" 2> "$work/error"; then
        die "$dialect oversized escaped literal admitted"
      fi
      grep -qxF 'Lexer Error: quoted literal exceeds 255-byte token limit' "$work/error"
      pass "$dialect oversized escaped spelling rejected"
    fi
  done
  for tail in "'abc" "'" "'abc''"; do
    printf 'PROGRAM p; BEGIN WRITELN(%s' "$tail" > "$work/unterminated.pas"
    if bin/pascal1981 --dialect "$dialect" "$work/unterminated.pas" -o "$work/unterminated" > "$work/output" 2> "$work/error"; then
      die "$dialect unterminated literal admitted"
    fi
    grep -qxF 'Lexer Error: unterminated quoted literal' "$work/error"
    pass "$dialect unterminated quoted literal rejected"
  done
done
finish 'quoted literal limits'
