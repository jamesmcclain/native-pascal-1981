#!/usr/bin/env bash
set -euo pipefail
"$1" unit_super_string.pas unit_super_string.impl -o "$2"
