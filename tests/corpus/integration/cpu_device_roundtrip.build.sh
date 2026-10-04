#!/usr/bin/env bash
set -euo pipefail
"$1" cpu_device_roundtrip.pas cpu_device_roundtrip.impl -o "$2"
