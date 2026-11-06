#!/usr/bin/env bash
# Two units with the same private (IMPLEMENTATION-only) names, linked with
# a program that declares the same names again (NEW-27).
set -euo pipefail

"$1" units_private_names.pas units_private_names.pa.impl \
  units_private_names.pb.impl -o "$2"
