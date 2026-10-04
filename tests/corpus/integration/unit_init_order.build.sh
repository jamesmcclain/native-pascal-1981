#!/usr/bin/env bash
# Builds a three-unit chain (base <- mid <- top <- program) where each
# unit's INITIALIZATION prints its own name -- proves EmitUnitInitCalls
# runs every USES'd unit's pascal_init_<name> exactly once, in
# dependency-before-dependent order, before the program's own body.
# See units_basic.build.sh for the general shape of a multi-compiland build.
set -euo pipefail

"$1" unit_init_order.pas unit_init_order.base.impl unit_init_order.mid.impl \
  unit_init_order.top.impl -o "$2"
