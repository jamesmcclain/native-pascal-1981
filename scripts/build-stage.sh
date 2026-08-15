#!/usr/bin/env bash
# Build one native (pascal1981-dialect) compiler stage into a standalone
# linked binary. Every stage USES jsonutil, so this always compiles and
# links jsonutil.pas's object file alongside the stage's own source.
#
# Usage: scripts/build-stage.sh <stage.pas> <output-binary> [extra clang args...]
#
# Extra clang args are appended to the link line, e.g. for codegen which needs LLVM:
#   scripts/build-stage.sh src/codegen.pas bin/codegen -L/usr/lib/llvm-20/lib -lLLVM-20
#
# By default both jsonutil.o and the stage itself are built via the
# host pascal1981 Python CLI (hybrid build). Opt-in env vars swap in native stages:
#
#   NATIVE_CODEGEN=<native-codegen-binary>
#   NATIVE_JSONUTIL=<native-codegen-binary>
#   NATIVE_LEXER=<native-lexer-binary>
#   NATIVE_PARSER=<native-parser-binary>
#   NATIVE_TYPECHECKER=<native-typechecker-binary>
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <stage.pas> <output-binary> [extra clang args...]" >&2
  exit 1
fi

stage_src="$1"
out_bin="$2"
shift 2
extra_args=("$@")

# The stages recurse (recursive-descent parsing, recursive AST lowering), and
# at -O0 every by-value Str255 argument gets its own spill slot, so one
# expression-nesting level costs ~114KB of frame. -O1 folds those away and
# brings the same level down to ~37KB -- an 8x cut in stack per unit of
# nesting. Override with STAGE_OPT= to build unoptimized.
STAGE_OPT="${STAGE_OPT--O1}"

src_dir="src"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Ensure runtime library exists
runtime_lib="runtime/build/libpascalrt.a"
if [ ! -f "$runtime_lib" ]; then
  make -C runtime >/dev/null
fi

jsonutil_obj="$work_dir/jsonutil.o"
stage_ll="$work_dir/$(basename "$stage_src" .pas).ll"

native_codegen="${NATIVE_CODEGEN:-}"
native_jsonutil="${NATIVE_JSONUTIL:-$native_codegen}"

run_frontend() {
  local src_file="$1"
  if [ -n "${NATIVE_LEXER:-}" ] && [ -n "${NATIVE_PARSER:-}" ] && [ -n "${NATIVE_TYPECHECKER:-}" ]; then
    "$NATIVE_LEXER" < "$src_file" | "$NATIVE_PARSER" | "$NATIVE_TYPECHECKER"
  else
    python3 -m pascal1981.cli_lex "$src_file" | \
      python3 -m pascal1981.cli_parse --source-file "$src_file" --dialect extended | \
      python3 -m pascal1981.cli_typecheck --source-file "$src_file" --dialect extended
  fi
}

(
  cd "$src_dir"
  if [ -n "$native_jsonutil" ]; then
    jsonutil_ll="$work_dir/jsonutil.ll"
    run_frontend jsonutil.pas | "$native_jsonutil" > "$jsonutil_ll"
    clang $STAGE_OPT -c "$jsonutil_ll" -o "$jsonutil_obj"
  else
    pascal1981 --dialect extended -c jsonutil.pas -o "$jsonutil_obj"
  fi
  if [ -n "$native_codegen" ]; then
    run_frontend "$(basename "$stage_src")" | "$native_codegen" > "$stage_ll"
  else
    pascal1981 --dialect extended -S "$(basename "$stage_src")" -o "$stage_ll"
  fi
)

mkdir -p "$(dirname "$out_bin")"
clang $STAGE_OPT "$stage_ll" "$jsonutil_obj" -lcjson \
  "${extra_args[@]}" \
  "$runtime_lib" \
  -o "$out_bin"

echo "built: $out_bin"
