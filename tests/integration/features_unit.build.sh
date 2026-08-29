#!/usr/bin/env bash
# Compile from src/ so the unit interface include resolves like stage builds.
set -euo pipefail

fixture_dir="$(pwd)"
cd ../../src
"$1" "$fixture_dir/features_unit.pas" features.pas -o "$2"
