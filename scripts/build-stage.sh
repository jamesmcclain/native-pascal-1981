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
# With no NATIVE_* variables this is a generation-1 build: every compiland is
# translated to C by bootstrap/build/pasboot and compiled by clang. Setting
# USE_PYTHON_REFERENCE=1 uses the external Python reference compiler
# (pascal1981) for generation 1 instead. Opt-in env vars swap in native stages:
#
#   NATIVE_CODEGEN=<native-codegen-binary>
#   NATIVE_JSONUTIL=<native-codegen-binary>
#   NATIVE_LEXER=<native-lexer-binary>
#   NATIVE_PARSER=<native-parser-binary>
#   NATIVE_TYPECHECKER=<native-typechecker-binary>
#
# DUMP_IR_DIR=<dir> keeps a copy of every LLVM IR file a native build writes
# (<dir>/<unit>.ll); scripts/cross-bootstrap-check.sh compares them.
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

USE_PYTHON_REFERENCE="${USE_PYTHON_REFERENCE:-1}"
bootstrap_dir="$(pwd)/bootstrap"
pasboot="$bootstrap_dir/build/pasboot"
if [ -z "${NATIVE_CODEGEN:-}" ] && [ "$USE_PYTHON_REFERENCE" != 1 ] && [ ! -x "$pasboot" ]; then
  make -C bootstrap >/dev/null
fi

jsonutil_obj="$work_dir/jsonutil.o"
stage_ll="$work_dir/$(basename "$stage_src" .pas).ll"
component_objs=()

native_codegen="${NATIVE_CODEGEN:-}"
native_jsonutil="${NATIVE_JSONUTIL:-$native_codegen}"

# codegen is a composition root over the cg_* units, so each one's
# implementation is compiled to its own object and linked alongside. Listed
# lowest layer first: cg_base holds the shared state and the LLVM-C/libc
# prototypes, then utilities, the type model and symbol tables, then the four
# lowering layers (expressions, I/O, statements, declarations), each of which
# only ever reaches downward. This holds for gen1 too: pasboot (and the Python
# reference) understand separately compiled units, so there is no monolithic
# fallback source to maintain.
stage_file="$(basename "$stage_src")"
component_units=()
if [ "$stage_file" = "codegen.pas" ]; then
  component_units=(argparse.pas features.pas cg_base.pas cg_util.pas cg_types.pas cg_symbols.pas cg_expr_shape.pas cg_expr_sets.pas cg_expr_support.pas cg_expr_literals.pas cg_expr_vector.pas cg_expr.pas cg_io.pas cg_stmt.pas cg_decl.pas)
elif [ "$stage_file" = "typechecker.pas" ]; then
  component_units=(argparse.pas features.pas tc_base.pas tc_types.pas tc_expr.pas tc_stmt.pas tc_decl.pas)
elif [ "$stage_file" = "parser.pas" ]; then
  component_units=(argparse.pas ps_base.pas ps_expr.pas ps_stmt.pas ps_decl.pas)
elif [ "$stage_file" = "driver.pas" ]; then
  # Not a compiler stage: the user-facing driver, built by the finished
  # compiler. It shares the argparse unit with the stages above.
  component_units=(argparse.pas)
elif [ "$stage_file" = "proxy.pas" ]; then
  # Not a compiler stage: the completion proxy, built by the finished
  # compiler. Same layering rule as the stages above -- lowest first, each
  # unit only reaching downward -- so bytebuf, which depends on nothing,
  # leads and proxycore, which depends on the rest, comes last.
  component_units=(bytebuf.pas argparse.pas jsonx.pas netsock.pas httpio.pas proxycore.pas)
fi

# The unit objects are compiled inside the ( cd "$src_dir" ... ) subshell below,
# but an array appended to inside a subshell does not survive it -- doing that
# silently dropped every component object from the link line, so the stage
# failed with undefined references to cg_base's exported state. Compute the
# paths here, in the parent shell, and let the subshell only create the files.
for unit_src in "${component_units[@]}"; do
  component_objs+=("$work_dir/${unit_src%.pas}.o")
done

run_frontend() {
  local src_file="$1"
  if [ -z "${NATIVE_LEXER:-}" ] || [ -z "${NATIVE_PARSER:-}" ] || [ -z "${NATIVE_TYPECHECKER:-}" ]; then
    echo "$0: NATIVE_CODEGEN needs NATIVE_LEXER, NATIVE_PARSER and NATIVE_TYPECHECKER" >&2
    exit 1
  fi
  "$NATIVE_LEXER" < "$src_file" | \
    "$NATIVE_PARSER" --dialect extended | \
    "$NATIVE_TYPECHECKER" --dialect extended
}

CLANG="${CLANG:-${CC:-clang}}"

# Keep a copy of a native build's IR when DUMP_IR_DIR is set.
dump_ir() {
  if [ -n "${DUMP_IR_DIR:-}" ]; then
    mkdir -p "$DUMP_IR_DIR"
    cp "$1" "$DUMP_IR_DIR/"
  fi
}

# Generation 1: compile one compiland without any Pascal compiler of our own.
# pasboot writes C, which clang compiles; -fwrapv gives Pascal's wrapping
# integer arithmetic. The Python reference writes an object (-c) or IR (-S).
gen1_compile() {
  local src_file="$1" out_file="$2" mode="$3"
  if [ "$USE_PYTHON_REFERENCE" = 1 ]; then
    pascal1981 --dialect extended "$mode" "$src_file" -o "$out_file"
  else
    local c_file="$work_dir/$(basename "$src_file" .pas).c"
    "$pasboot" "$src_file" -o "$c_file"
    "$CLANG" $STAGE_OPT -fwrapv -w -I"$bootstrap_dir" -c "$c_file" -o "$out_file"
  fi
}

# A pasboot build links the stage's object; the other builds link its IR.
stage_input="$stage_ll"
if [ -z "$native_codegen" ] && [ "$USE_PYTHON_REFERENCE" != 1 ]; then
  stage_input="$work_dir/$(basename "$stage_src" .pas).o"
fi

(
  cd "$src_dir"
  if [ -n "$native_jsonutil" ]; then
    jsonutil_ll="$work_dir/jsonutil.ll"
    run_frontend jsonutil.pas | "$native_jsonutil" --dialect extended > "$jsonutil_ll"
    dump_ir "$jsonutil_ll"
    "$CLANG" $STAGE_OPT -c "$jsonutil_ll" -o "$jsonutil_obj"
  else
    gen1_compile jsonutil.pas "$jsonutil_obj" -c
  fi
  for unit_src in "${component_units[@]}"; do
    unit_name="${unit_src%.pas}"
    unit_ll="$work_dir/$unit_name.ll"
    unit_obj="$work_dir/$unit_name.o"
    if [ -n "$native_codegen" ]; then
      run_frontend "$unit_src" | "$native_codegen" --dialect extended > "$unit_ll"
      dump_ir "$unit_ll"
      "$CLANG" $STAGE_OPT -c "$unit_ll" -o "$unit_obj"
    elif [ "$USE_PYTHON_REFERENCE" = 1 ]; then
      gen1_compile "$unit_src" "$unit_ll" -S
      "$CLANG" $STAGE_OPT -c "$unit_ll" -o "$unit_obj"
    else
      gen1_compile "$unit_src" "$unit_obj" -c
    fi
  done
  if [ -n "$native_codegen" ]; then
    run_frontend "$stage_file" | "$native_codegen" --dialect extended > "$stage_ll"
    dump_ir "$stage_ll"
  elif [ "$USE_PYTHON_REFERENCE" = 1 ]; then
    gen1_compile "$stage_file" "$stage_ll" -S
  else
    gen1_compile "$stage_file" "$stage_input" -c
  fi
)

mkdir -p "$(dirname "$out_bin")"
"$CLANG" $STAGE_OPT "$stage_input" "$jsonutil_obj" "${component_objs[@]}" -lcjson \
  "${extra_args[@]}" \
  "$runtime_lib" \
  -o "$out_bin"

echo "built: $out_bin"
