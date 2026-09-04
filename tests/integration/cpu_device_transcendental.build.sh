#!/usr/bin/env bash
set -euo pipefail
"$1" cpu_device_transcendental.pas cpu_device_transcendental.impl -o "$2"
