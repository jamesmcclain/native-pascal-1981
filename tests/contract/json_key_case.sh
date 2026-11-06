#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Compiler JSON key lookups are case-sensitive, so a lower-case per-site
# snapshot (indexck, mathck, rangeck) never matches an upper-case directive
# entry (INDEXCK, MATHCK, RANGECK) of a meta_flags/read_flags object.
(
  cd src
  "$ROOT/bin/pascal1981" --dialect extended \
    ../tests/contract/fixtures/json_key_case_check.pas jsonutil.pas \
    -o "$work/check"
)
"$work/check" > "$work/actual"
printf '%s\n' 'FALSE FALSE' 'FALSE FALSE' 'TRUE TRUE' 'FALSE TRUE' 'Probe' \
  > "$work/expected"
diff -u "$work/expected" "$work/actual"
# No compiler stage may use cJSON's case-insensitive object lookup.
if grep -nE '\bcJSON_GetObjectItem\b' src/*.pas src/*.inc; then
  echo 'FAIL: case-insensitive cJSON_GetObjectItem in src/' >&2
  exit 1
fi
echo 'PASS: compiler JSON key lookups are case-sensitive'
