#!/usr/bin/env bash
# Cross-bootstrap identity check: build generation 1 twice -- once with
# pasboot, the in-tree C bootstrap translator, and once with the external
# Python reference compiler -- then build generation 2 from each and require
# the two to be byte-identical.
#
# Generation 2 is written by the generation-1 stage binaries, which run the
# same algorithm whichever compiler built them, so any difference means one
# of the two generation-1 builds miscompiled a stage. The per-unit IR is
# compared as well as the linked binaries, so a divergence names its unit.
#
# Needs pascal1981 (the Python reference) on PATH.
#
# Usage: scripts/cross-bootstrap-check.sh [work-dir]
#   The work directory (default: a fresh temporary one, deleted afterward)
#   keeps both builds and their IR for inspection when given.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v pascal1981 >/dev/null 2>&1; then
  echo "cross-bootstrap-check: pascal1981 (the Python reference compiler) is not on PATH" >&2
  exit 1
fi

if [ "$#" -ge 1 ]; then
  work="$1"
  mkdir -p "$work"
  work="$(cd "$work" && pwd)"
else
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
fi

LLVM_CONFIG="${LLVM_CONFIG:-$(command -v llvm-config 2>/dev/null || command -v llvm-config-20 2>/dev/null || echo llvm-config)}"
# --ldflags and --libs print one line each; split both into words.
read -r -d '' -a llvm_flags < <("$LLVM_CONFIG" --ldflags --libs) || true

make -C runtime >/dev/null
make -C bootstrap >/dev/null

stages=(lexer parser typechecker codegen)

stage_args() {
  if [ "$1" = codegen ]; then
    printf '%s\n' "${llvm_flags[@]}"
  fi
}

for flavor in pasboot python; do
  use_python=0
  [ "$flavor" = python ] && use_python=1
  for st in "${stages[@]}"; do
    mapfile -t extra < <(stage_args "$st")
    USE_PYTHON_REFERENCE=$use_python ./scripts/build-stage.sh "src/$st.pas" "$work/$flavor/gen1/$st" "${extra[@]}" >/dev/null
  done
  g1="$work/$flavor/gen1"
  for st in "${stages[@]}"; do
    mapfile -t extra < <(stage_args "$st")
    rm -rf "$work/$flavor/ir/$st"
    DUMP_IR_DIR="$work/$flavor/ir/$st" \
      NATIVE_LEXER="$g1/lexer" NATIVE_PARSER="$g1/parser" NATIVE_TYPECHECKER="$g1/typechecker" NATIVE_CODEGEN="$g1/codegen" \
      ./scripts/build-stage.sh "src/$st.pas" "$work/$flavor/gen2/$st" "${extra[@]}" >/dev/null
  done
  echo "cross-bootstrap-check: built gen1 and gen2 with $flavor"
done

status=0
units=0
for st in "${stages[@]}"; do
  for ll in "$work/python/ir/$st"/*.ll; do
    units=$((units + 1))
    unit="$(basename "$ll")"
    if ! cmp -s "$ll" "$work/pasboot/ir/$st/$unit"; then
      echo "cross-bootstrap-check: gen2 IR differs: $st/$unit" >&2
      status=1
    fi
  done
  if [ "$(ls "$work/python/ir/$st")" != "$(ls "$work/pasboot/ir/$st")" ]; then
    echo "cross-bootstrap-check: gen2 IR file sets differ for $st" >&2
    status=1
  fi
  if ! cmp -s "$work/python/gen2/$st" "$work/pasboot/gen2/$st"; then
    echo "cross-bootstrap-check: gen2 binaries differ: $st" >&2
    status=1
  fi
done

if [ "$status" = 0 ]; then
  echo "cross-bootstrap-check: OK -- $units gen2 IR files and ${#stages[@]} gen2 binaries identical"
fi
exit "$status"
