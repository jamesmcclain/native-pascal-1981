#!/usr/bin/env bash
# Compiles from src/ because (*$INCLUDE:...*) resolves against the working
# directory, the same reason scripts/build-stage.sh cds into the source dir.
set -euo pipefail

fixture_dir="$(pwd)"
cd ../../src
"$1" --dialect extended "$fixture_dir/transforms.pas" bytebuf.pas jsonx.pas netsock.pas \
     httpio.pas proxycore.pas \
     -o "$2"
