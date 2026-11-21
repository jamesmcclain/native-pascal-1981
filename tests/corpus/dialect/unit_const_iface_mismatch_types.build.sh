#!/usr/bin/env bash
set -euo pipefail
"$1" unit_const_iface_mismatch_types.pas -o "$2"
