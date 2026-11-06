#!/usr/bin/env bash
set -euo pipefail
"$1" cpu_device_index_shadowing.pas cpu_device_index_shadowing.impl -o "$2"
