#!/usr/bin/env bash
set -euo pipefail
fixture_dir="$(pwd)"
cd ../../src
"$1" "$fixture_dir/argparse_passthru.pas" argparse.pas -o "$2"
