#!/usr/bin/env bash
set -euo pipefail
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$fixture_dir/../../src"
"$1" --dialect extended "$fixture_dir/conformance_raw.pas" bytebuf.pas argparse.pas netsock.pas sysutil.pas -o "$2"
