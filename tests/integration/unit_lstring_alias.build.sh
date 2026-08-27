#!/usr/bin/env bash
set -euo pipefail
"$1" unit_lstring_alias.pas unit_lstring_alias.impl -o "$2"
