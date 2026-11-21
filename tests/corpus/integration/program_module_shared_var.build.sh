#!/usr/bin/env bash
# NEW-46: a PROGRAM and a MODULE that both declare VAR v link cleanly with
# independent storage (program-level globals are internal unless [PUBLIC]).
set -euo pipefail

"$1" program_module_shared_var.pas program_module_shared_var.module -o "$2"
