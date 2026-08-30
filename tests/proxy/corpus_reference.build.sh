#!/usr/bin/env bash
# Compile from src so Pascal INCLUDE paths resolve beside their units.
set -euo pipefail

fixture_dir="$(pwd)"
cd ../../src
"$1" --dialect extended "$fixture_dir/corpus_reference.pas" bytebuf.pas jsonx.pas sysutil.pas \
     -o "$2"
