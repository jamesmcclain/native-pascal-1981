#!/usr/bin/env bash
set -euo pipefail
"$1" unit_interface_forward.pas unit_interface_forward.impl -o "$2"
