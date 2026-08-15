#!/usr/bin/env bash
# End-to-end multi-generational bootstrap:
#   Gen 1 (Hybrid) -> Gen 2 (Native) -> Gen 3 -> Gen 4 -> Fixed-point verification
#
# Copies verified fixed-point binaries to bin/ upon success.
set -euo pipefail
cd "$(dirname "$0")/.."

LLVM_LIB_DIR="${LLVM_LIB_DIR:-/usr/lib/llvm-20/lib}"
LLVM_LINK_FLAGS=("-L${LLVM_LIB_DIR}" "-lLLVM-20")

echo "=== Building C runtime library ==="
make -C runtime

echo "=== Generation 1: Hybrid build from Python reference ==="
mkdir -p build/gen1
./scripts/build-stage.sh src/lexer.pas build/gen1/lexer
./scripts/build-stage.sh src/parser.pas build/gen1/parser
./scripts/build-stage.sh src/typechecker.pas build/gen1/typechecker
./scripts/build-stage.sh src/codegen.pas build/gen1/codegen "${LLVM_LINK_FLAGS[@]}"

echo "=== Generation 2: Self-hosted build using Gen 1 binaries ==="
mkdir -p build/gen2
NATIVE_LEXER="$(pwd)/build/gen1/lexer" \
NATIVE_PARSER="$(pwd)/build/gen1/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen1/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen1/codegen" \
./scripts/build-stage.sh src/lexer.pas build/gen2/lexer

NATIVE_LEXER="$(pwd)/build/gen1/lexer" \
NATIVE_PARSER="$(pwd)/build/gen1/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen1/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen1/codegen" \
./scripts/build-stage.sh src/parser.pas build/gen2/parser

NATIVE_LEXER="$(pwd)/build/gen1/lexer" \
NATIVE_PARSER="$(pwd)/build/gen1/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen1/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen1/codegen" \
./scripts/build-stage.sh src/typechecker.pas build/gen2/typechecker

NATIVE_LEXER="$(pwd)/build/gen1/lexer" \
NATIVE_PARSER="$(pwd)/build/gen1/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen1/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen1/codegen" \
./scripts/build-stage.sh src/codegen.pas build/gen2/codegen "${LLVM_LINK_FLAGS[@]}"

echo "=== Generation 3: Self-hosted build using Gen 2 binaries ==="
mkdir -p build/gen3
NATIVE_LEXER="$(pwd)/build/gen2/lexer" \
NATIVE_PARSER="$(pwd)/build/gen2/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen2/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen2/codegen" \
./scripts/build-stage.sh src/lexer.pas build/gen3/lexer

NATIVE_LEXER="$(pwd)/build/gen2/lexer" \
NATIVE_PARSER="$(pwd)/build/gen2/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen2/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen2/codegen" \
./scripts/build-stage.sh src/parser.pas build/gen3/parser

NATIVE_LEXER="$(pwd)/build/gen2/lexer" \
NATIVE_PARSER="$(pwd)/build/gen2/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen2/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen2/codegen" \
./scripts/build-stage.sh src/typechecker.pas build/gen3/typechecker

NATIVE_LEXER="$(pwd)/build/gen2/lexer" \
NATIVE_PARSER="$(pwd)/build/gen2/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen2/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen2/codegen" \
./scripts/build-stage.sh src/codegen.pas build/gen3/codegen "${LLVM_LINK_FLAGS[@]}"

echo "=== Generation 4: Self-hosted build using Gen 3 binaries ==="
mkdir -p build/gen4
NATIVE_LEXER="$(pwd)/build/gen3/lexer" \
NATIVE_PARSER="$(pwd)/build/gen3/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen3/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen3/codegen" \
./scripts/build-stage.sh src/lexer.pas build/gen4/lexer

NATIVE_LEXER="$(pwd)/build/gen3/lexer" \
NATIVE_PARSER="$(pwd)/build/gen3/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen3/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen3/codegen" \
./scripts/build-stage.sh src/parser.pas build/gen4/parser

NATIVE_LEXER="$(pwd)/build/gen3/lexer" \
NATIVE_PARSER="$(pwd)/build/gen3/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen3/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen3/codegen" \
./scripts/build-stage.sh src/typechecker.pas build/gen4/typechecker

NATIVE_LEXER="$(pwd)/build/gen3/lexer" \
NATIVE_PARSER="$(pwd)/build/gen3/parser" \
NATIVE_TYPECHECKER="$(pwd)/build/gen3/typechecker" \
NATIVE_CODEGEN="$(pwd)/build/gen3/codegen" \
./scripts/build-stage.sh src/codegen.pas build/gen4/codegen "${LLVM_LINK_FLAGS[@]}"

echo "=== Verifying Fixed-Point Identity (Gen 3 vs Gen 4) ==="
cmp build/gen3/lexer build/gen4/lexer
cmp build/gen3/parser build/gen4/parser
cmp build/gen3/typechecker build/gen4/typechecker
cmp build/gen3/codegen build/gen4/codegen

echo "=== Installing fixed-point binaries to bin/ ==="
mkdir -p bin
cp build/gen4/lexer bin/lexer
cp build/gen4/parser bin/parser
cp build/gen4/typechecker bin/typechecker
cp build/gen4/codegen bin/codegen

echo "=== Bootstrap successfully verified! Fixed-point binaries installed in bin/ ==="
