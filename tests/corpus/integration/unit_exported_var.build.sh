#!/usr/bin/env bash
set -euo pipefail
"$1" unit_exported_var.pas unit_exported_var.impl -o "$2"
