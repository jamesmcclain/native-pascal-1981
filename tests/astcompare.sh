#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.."

passed=0
failed=0
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

pass() { echo "PASS: $1"; passed=$((passed + 1)); }
fail() { echo "FAIL: $1" >&2; failed=$((failed + 1)); }

write_pair() {
  printf '%s\n' "$1" > "$work_dir/expected.json"
  printf '%s\n' "$2" > "$work_dir/actual.json"
}

expect_match() {
  local label=$1
  shift
  if bin/astcompare "$@" >"$work_dir/out" 2>"$work_dir/err"; then
    pass "$label"
  else
    fail "$label"
    cat "$work_dir/err" >&2
  fi
}

expect_mismatch() {
  local label=$1 diagnostic=$2
  shift 2
  local status=0
  bin/astcompare "$@" >"$work_dir/out" 2>"$work_dir/err" || status=$?
  if [ "$status" -ne 0 ] && grep -qF "$diagnostic" "$work_dir/err"; then
    pass "$label"
  else
    fail "$label"
    echo "status: $status" >&2
    cat "$work_dir/err" >&2
  fi
}

write_pair '{"name":"node","items":[1,true,false,null]}' \
  '{"name":"node","items":[1,true,false,null]}'
expect_match 'identical JSON matches' "$work_dir/expected.json" "$work_dir/actual.json"

write_pair '{"a":1,"b":{"x":2,"y":3}}' '{"b":{"y":3,"x":2},"a":1.0}'
expect_match 'object key order is ignored' "$work_dir/expected.json" "$work_dir/actual.json"

write_pair '{"resolved_type":"INTEGER","child":{"resolved_type":"REAL","x":1}}' \
  '{"resolved_type":"REAL","child":{"resolved_type":null,"x":1}}'
expect_match 'ignored keys are skipped recursively' --ignore-key resolved_type \
  "$work_dir/expected.json" "$work_dir/actual.json"

write_pair '{"items":[1,2]}' '{"items":[2,1]}'
expect_mismatch 'array order remains significant' 'Mismatch at $.items[0]' \
  "$work_dir/expected.json" "$work_dir/actual.json"

write_pair '{"outer":{"wanted":1}}' '{"outer":{}}'
expect_mismatch 'missing keys report a JSON path' 'Mismatch at $.outer.wanted' \
  "$work_dir/expected.json" "$work_dir/actual.json"

write_pair '{"outer":{}}' '{"outer":{"extra":1}}'
expect_mismatch 'extra keys report a JSON path' 'Mismatch at $.outer.extra' \
  "$work_dir/expected.json" "$work_dir/actual.json"

write_pair '{"value":"1"}' '{"value":1}'
expect_mismatch 'different JSON types do not compare equal' 'JSON types differ' \
  "$work_dir/expected.json" "$work_dir/actual.json"

write_pair '{"items":[1]}' '{"items":[1,2]}'
expect_mismatch 'different array lengths fail' 'array lengths differ' \
  "$work_dir/expected.json" "$work_dir/actual.json"

printf '%s\n' '{broken' > "$work_dir/actual.json"
expect_mismatch 'malformed JSON fails' 'malformed JSON in actual file' \
  "$work_dir/expected.json" "$work_dir/actual.json"

expect_mismatch 'missing files fail' 'cannot read expected file' \
  "$work_dir/absent.json" "$work_dir/actual.json"

expect_mismatch 'invalid command lines fail' 'Usage: astcompare' --bad-option \
  "$work_dir/expected.json" "$work_dir/actual.json"

echo "========================================"
echo "astcompare results: $passed passed, $failed failed"
echo "========================================"

[ "$failed" -eq 0 ]
