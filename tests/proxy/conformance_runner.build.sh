#!/usr/bin/env bash
set -euo pipefail
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$fixture_dir/../../src"
"$1" "$fixture_dir/conformance_runner.pas" bytebuf.pas argparse.pas netsock.pas jsonx.pas httpio.pas sysutil.pas -o "$2"
