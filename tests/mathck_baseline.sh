#!/usr/bin/env bash
# Persisted G1–G29 baseline; Python isolates crashes and bounds loop execution.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tests/mathck_baseline.py
