#!/usr/bin/env bash
# Builds a diamond USES graph: beta and gamma both depend on alpha. Each
# compiland gets the interfaces it needs spliced in; the driver compiles and
# links all four sources in one invocation.
set -euo pipefail

"$1" units_graph.pas units_graph.alpha.impl units_graph.beta.impl \
  units_graph.gamma.impl -o "$2"
