#!/usr/bin/env bash
# A MODULE compiland exports routines consumed through a separate UNIT header.
set -euo pipefail

"$1" module_compiland.pas module_compiland.module -o "$2"
