#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# The corpus runner's negative-compile checks reject wrong status, stdout and output files.
#
# Each faulty fixture must fail at its own check; the control must pass.
require bin/pascal1981-native

fx=$work/fx
mkdir -p "$fx"
printf 'PROGRAM A;\nBEGIN\n  x := 1;\nEND.\n' > "$fx/control.pas"
echo 1 > "$fx/control.exitcode"
printf 'PROGRAM A;\nBEGIN\n  x := 1;\nEND.\n' > "$fx/status.pas"
echo 2 > "$fx/status.exitcode"
for name in stdout artifact; do
  printf 'PROGRAM B;\nBEGIN\nEND.\n' > "$fx/$name.pas"
  echo 1 > "$fx/$name.exitcode"
done
printf '#!/usr/bin/env bash\necho noise\nexit 1\n' > "$fx/stdout.build.sh"
printf '#!/usr/bin/env bash\ntouch "$2"\nexit 1\n' > "$fx/artifact.build.sh"

run_fixture() { # name: run one fixture, leaving its output in $work/name.log
  local status=0
  bash tests/corpus/fixtures.sh -j 1 "$fx/$1.pas" > "$work/$1.log" 2>&1 ||
    status=$?
  return "$status"
}

if run_fixture control &&
   grep -qF "PASS: $fx/control.pas (expected compilation failure)" \
     "$work/control.log"; then
  pass "a compile failing with the expected status passes"
else
  fail "a compile failing with the expected status passes"
  cat "$work/control.log" >&2
fi

expect_rejected() { # name message label
  if ! run_fixture "$1" && grep -qF "FAIL: $fx/$1.pas ($2)" "$work/$1.log"; then
    pass "$3"
  else
    fail "$3"
    cat "$work/$1.log" >&2
  fi
}

expect_rejected status 'expected compile exit code 2, got 1' \
  "a wrong compile exit status is rejected"
expect_rejected stdout 'a failed compile wrote to stdout' \
  "a failed compile that writes stdout is rejected"
expect_rejected artifact 'a failed compile left an output file' \
  "a failed compile that leaves an output file is rejected"

finish 'Fixture negative'
