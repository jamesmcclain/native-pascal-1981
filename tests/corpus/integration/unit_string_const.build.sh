#!/usr/bin/env bash
set -euo pipefail
"$1" unit_string_const.pas unit_string_const.impl -o "$2"
