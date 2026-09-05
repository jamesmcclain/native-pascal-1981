#!/usr/bin/env bash
set -euo pipefail
"$1" cpu_device_builtin_shadowing.pas cpu_device_builtin_shadowing.impl -o "$2"
