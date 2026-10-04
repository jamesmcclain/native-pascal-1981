#!/usr/bin/env bash
set -euo pipefail
"$1" unit_iface_const_repeat.pas unit_iface_const_repeat.impl -o "$2"
