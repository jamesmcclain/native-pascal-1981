#!/usr/bin/env bash
set -euo pipefail
"$1" cpu_device_uses_rename.pas cpu_device_launch.impl -o "$2"
