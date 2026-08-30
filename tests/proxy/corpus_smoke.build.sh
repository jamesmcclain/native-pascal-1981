#!/usr/bin/env bash
set -euo pipefail
fixture_dir="$(pwd)"
cd ../../src
"$1" --dialect extended "$fixture_dir/corpus_smoke.pas" bytebuf.pas argparse.pas netsock.pas jsonx.pas httpio.pas sysutil.pas -o "$2"
