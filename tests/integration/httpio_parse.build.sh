#!/usr/bin/env bash
# Compiles from src/ because (*$INCLUDE:...*) resolves against the working
# directory, the same reason scripts/build-stage.sh cds into the source dir.
set -euo pipefail

fixture_dir="$(pwd)"
cd ../../src
"$1" "$fixture_dir/httpio_parse.pas" bytebuf.pas netsock.pas httpio.pas -o "$2"
