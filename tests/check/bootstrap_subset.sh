#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Every gen1 compiland stays inside the subset pasboot translates.
#
# See docs/bootstrap_subset.md. The check is parse-only, so a src/ change that leaves the
# subset fails here, in seconds, naming the construct and line, rather than
# deep inside a gen1 build. The Makefile owns the list of compilands.
set +e
require bootstrap/build/pasboot
compilands=$(MAKEFLAGS= make -s --no-print-directory print-gen1-compilands) ||
  die 'cannot list the gen1 compilands'
for unit in $compilands; do
  if bootstrap/build/pasboot --parse-only "src/$unit.pas"; then
    pass
  else
    fail "src/$unit.pas is outside the bootstrap subset"
  fi
done
finish "bootstrap subset"
