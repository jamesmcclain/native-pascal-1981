#!/usr/bin/env bash
set -euo pipefail
"$1" runtime_secondary_link.pas runtime_secondary_link.impl -o "$2"
