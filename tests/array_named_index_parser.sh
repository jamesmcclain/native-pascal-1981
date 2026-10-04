#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# Parser coverage for named ordinal array index types: every bare index
# name parses to a NamedType node, pretty81 round-trips it losslessly, and
# the SUPER ARRAY lo..* grammar is unchanged.
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for dialect in vintage extended; do
  for kind in boolean enum subrange char; do
    source="tests/golden/array_named_$kind.pas"
    bin/lexer --dialect "$dialect" < "$source" | bin/parser --dialect "$dialect" > "$work/parsed.json"
    # Each fixture has a named type and its explicit-range equivalent.
    jq -e '[.. | objects | select(.__node_type__? == "ArrayType") | .index_range.__node_type__] |
      index("NamedType") != null and index("IndexRange") != null' "$work/parsed.json" > /dev/null
    bin/pretty81 < "$work/parsed.json" > "$work/pretty.pas"
    bin/lexer --dialect "$dialect" < "$work/pretty.pas" | bin/parser --dialect "$dialect" > "$work/reparsed.json"
    # Pretty-printing must retain the distinction, not invent a low bound.
    jq -c '[.. | objects | select(.__node_type__? == "ArrayType") | .index_range]' \
      "$work/parsed.json" > "$work/before"
    jq -c '[.. | objects | select(.__node_type__? == "ArrayType") | .index_range]' \
      "$work/reparsed.json" > "$work/after"
    diff -u "$work/before" "$work/after"
    echo "PASS: $kind $dialect parser/pretty round-trip"
  done
done

# A super-array lower bound remains a range, never a type name.
printf 'PROGRAM s(output); TYPE A = SUPER ARRAY [lo..*] OF INTEGER; CONST lo = 1; BEGIN END.\n' > "$work/super.pas"
bin/lexer < "$work/super.pas" | bin/parser > "$work/super.json"
jq -e '[.. | objects | select(.__node_type__? == "ArrayType" and .super == true) |
  .index_range | select(.__node_type__ == "IndexRange" and .low.name == "lo" and .high == null)] |
  length == 1' "$work/super.json" > /dev/null
echo 'PASS: SUPER ARRAY lower-bound grammar unchanged'
