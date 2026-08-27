#!/usr/bin/env bash
set -euo pipefail
"$1" units_cbare_pascal_body.pas units_cbare_pascal_body.cabi.impl -o "$2"
