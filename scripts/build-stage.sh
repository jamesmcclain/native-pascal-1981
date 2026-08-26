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
component_objs=()

native_codegen="${NATIVE_CODEGEN:-}"
native_jsonutil="${NATIVE_JSONUTIL:-$native_codegen}"

# codegen is a composition root over the cg_base unit, so its implementation
# is compiled to its own object and linked alongside.  This holds for gen1 too:
# the Python reference understands separately compiled units, so there is no
# monolithic fallback source to maintain.
stage_file="$(basename "$stage_src")"
component_units=()
if [ "$stage_file" = "codegen.pas" ]; then
  component_units=(cg_base.pas cg_util.pas cg_types.pas)
fi

# The unit objects are compiled inside the ( cd "$src_dir" ... ) subshell below,
# but an array appended to inside a subshell does not survive it -- doing that
# silently dropped every component object from the link line, so the stage
# failed with undefined references to cg_base's exported state. Compute the
# paths here, in the parent shell, and let the subshell only create the files.
for unit_src in "${component_units[@]}"; do
  component_objs+=("$work_dir/${unit_src%.pas}.o")
done

PYTHON="${PYTHON:-python3}"

run_frontend() {
  local src_file="$1"
  if [ -n "${NATIVE_LEXER:-}" ] && [ -n "${NATIVE_PARSER:-}" ] && [ -n "${NATIVE_TYPECHECKER:-}" ]; then
    "$NATIVE_LEXER" < "$src_file" | "$NATIVE_PARSER" | "$NATIVE_TYPECHECKER"
  else
    "$PYTHON" -m pascal1981.cli_lex "$src_file" | \
      "$PYTHON" -m pascal1981.cli_parse --source-file "$src_file" --dialect extended | \
      "$PYTHON" -m pascal1981.cli_typecheck --source-file "$src_file" --dialect extended
  fi
}

CLANG="${CLANG:-${CC:-clang}}"

(
  cd "$src_dir"
  if [ -n "$native_jsonutil" ]; then
    jsonutil_ll="$work_dir/jsonutil.ll"
    run_frontend jsonutil.pas | "$native_jsonutil" > "$jsonutil_ll"
    "$CLANG" $STAGE_OPT -c "$jsonutil_ll" -o "$jsonutil_obj"
  else
    pascal1981 --dialect extended -c jsonutil.pas -o "$jsonutil_obj"
  fi
  for unit_src in "${component_units[@]}"; do
    unit_name="${unit_src%.pas}"
    unit_ll="$work_dir/$unit_name.ll"
    unit_obj="$work_dir/$unit_name.o"
    if [ -n "$native_codegen" ]; then
      run_frontend "$unit_src" | "$native_codegen" > "$unit_ll"
    else
      pascal1981 --dialect extended -S "$unit_src" -o "$unit_ll"
    fi
    "$CLANG" $STAGE_OPT -c "$unit_ll" -o "$unit_obj"
  done
  if [ -n "$native_codegen" ]; then
    run_frontend "$stage_file" | "$native_codegen" > "$stage_ll"
  else
    pascal1981 --dialect extended -S "$stage_file" -o "$stage_ll"
  fi
)

mkdir -p "$(dirname "$out_bin")"
"$CLANG" $STAGE_OPT "$stage_ll" "$jsonutil_obj" "${component_objs[@]}" -lcjson \
  "${extra_args[@]}" \
  "$runtime_lib" \
  -o "$out_bin"

echo "built: $out_bin"
