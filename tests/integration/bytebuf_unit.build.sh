#!/usr/bin/env bash
# The unit under test lives in src/, and (*$INCLUDE:...*) resolves against the
# working directory, so the compile has to run from there -- the same reason
# scripts/build-stage.sh cds into the source directory.
set -euo pipefail

fixture_dir="$(pwd)"
cd ../../src
"$1" "$fixture_dir/bytebuf_unit.pas" bytebuf.pas -o "$2"
