# Native Pascal 1981 Compiler

This repository contains a native compiler for the 1981 IBM Pascal dialect. It targets LLVM IR, the System V AMD64 ABI, and NVIDIA NVPTX.

<img width="1536" height="864" alt="image" src="https://github.com/user-attachments/assets/f59a2d0f-468b-41b2-838c-b76729f15975" />

> **If you write Pascal in this repository,** read
> [`docs/dialect_notes.md`](docs/dialect_notes.md) first. The notes cover
> what the vintage and extended dialects each provide. They show the width
> of each integer type. They list the constructs that fail without an error.
> For example, `TRUNC` narrows the result to 16 bits.

## System Prerequisites

Install these packages before you build the toolchain (for example, on Debian or Ubuntu Linux x86_64):

- `clang` (C compiler and linker)
- `make` (build tool)
- `libllvm-20-dev` / `llvm-20` (LLVM 20 library and headers)
- `libcjson-dev` (cJSON library and headers)
- `indent` (C code formatting tool)
- `python3` and `pip3` with the reference compiler package:
  ```bash
  pip3 install 'https://github.com/jamesmcclain/pascal-1981/archive/5fe71893fd8b16a415a6c67c2fad12bd729e7279.zip'
  ```

## Repository Layout

- `src/`: Native compiler stages and driver in Pascal (`lexer.pas`, `parser.pas`, `typechecker.pas`, `codegen.pas`, `driver.pas`, `jsonutil.pas`, `jsonutil.inc`). The codegen stage is a composition root over fourteen separately compiled units. Each unit has a `.inc` interface and a `.pas` implementation. The units layer lowest first. Each unit depends only on units at a lower layer:
  - `argparse`: command-line argument parsing (shared by parser, typechecker, and codegen).
  - `features`: shared language-feature resolution for the two dialects.
  - `cg_base`: shared compiler state, LLVM-C and libc prototypes, constants and record types.
  - `cg_util`: diagnostics, depth guards, string and pointer-array helpers.
  - `cg_types`: the type registry, sizing and layout, constant folding, SysV classification.
  - `cg_symbols`: symbol, scope and routine tables.
  - `cg_expr_shape`: type-only expression-shape queries. It emits no IR.
  - `cg_expr_sets`: set operations on already-evaluated operands.
  - `cg_expr_support`: leaf expression-lowering helpers. It never evaluates an AST node.
  - `cg_expr_literals`: leaf lowering for assignments from compile-time string literals.
  - `cg_expr_vector`: lowering for `VECTOR [n] OF scalar` operations.
  - `cg_expr`: expression lowering.
  - `cg_io`: WRITE/READ lowering.
  - `cg_stmt`: statement lowering.
  - `cg_decl`: declaration lowering.
- `runtime/`: C runtime static library and headers (`libpascalrt.a`, `pascalrt.h`).
- `bin/`: Compiler driver (`pascal1981-native`, alias `pascal1981`) and stage binaries (`lexer`, `parser`, `typechecker`, `codegen`).
- `scripts/`: Build scripts (`build-stage.sh`), formatting scripts (`beautify.sh`), and git hooks (`scripts/hooks`). To enable the pre-commit formatting hook, run `git config core.hooksPath scripts/hooks` once per clone. This setting is local config. A fresh checkout does not enable the hook. The root `Makefile` drives the multi-generation bootstrap with the `bootstrap` target. It is not a standalone script.
- `tests/`: Test suites (golden files, unit tests, integration tests, dialect fixtures).
- `docs/`: The [EBNF grammar](docs/ebnf_grammar.md) of the dialect. The dialect notes cover [widths, literals, and silent failure modes](docs/dialect_notes.md).

## Building

To build the runtime, the driver, and all compiler stages (bootstrap):
```bash
make
```

By default, the build uses `llvm-config` to determine the LLVM linker flags and libraries. If `llvm-config` is not in PATH, the build uses `llvm-config-20`. You can override the default by setting `LLVM_CONFIG`:
```bash
LLVM_CONFIG=llvm-config-20 make
```
You can also override the C compiler/linker (default `clang`) with `CC`:
```bash
CC=clang-20 make
```

To rebuild only the four compiler stages, run:
```bash
make bootstrap
```
Then build the installed Pascal driver from the fixed-point stages:
```bash
make driver
```

The bootstrap process has four steps:
1. **Generation 1 (Hybrid)**: Builds the native compiler stages with the Python reference compiler (`pascal1981`).
2. **Generation 2 (Self-hosted)**: Recompiles all native compiler stages with the Generation 1 binaries.
3. **Generation 3 (Self-hosted)**: Recompiles all native compiler stages with the Generation 2 binaries.
4. **Generation 4 (Fixed Point)**: Recompiles all native compiler stages with the Generation 3 binaries and verifies binary identity (`cmp`). `make driver` then compiles `src/driver.pas` with the fixed-point stages and installs it as `bin/pascal1981-native` (with `bin/pascal1981` as its alias).

### Compiling a Program
To compile a Pascal program with the native compiler, run:
```bash
bin/pascal1981-native hello.pas -o hello
./hello
```

Supported options:
- `-o <file>`: Set output path
- `-c`: Compile to object file (`.o`)
- `-S`: Emit LLVM IR (`.ll`)
- `-O0`, `-O1`, `-O2`, `-O3`: Set optimization level
- `--emit-ptx`: Emit NVPTX assembly for device kernels
- `-v`: Print pipeline commands

## Running Tests

Run the routine test suites:

```bash
make test
```

This target runs the driver, sysutil, native, proxy, and pre-commit-hook test groups. The test runners do not require pytest. The proxy tests need `python3`.

This target does not run the reference-parity, bootstrap, or Emacs tests.

Use these targets for a specific test group:

| Target | Test group |
| --- | --- |
| `make test-driver` | Driver, golden-file, and IR/PTX-text directive tests. No Python needed. |
| `make test-native` | Routine native compiler tests |
| `make test-sysutil` | POSIX filesystem and process primitives, exercised from Pascal |
| `make test-proxy` | Differential conformance for the completion proxy (needs `python3`) |
| `make test-gpu` | CUDA compilation and execution on an NVIDIA GPU |
| `make test-reference-parity` | Native compiler parity with the Python reference compiler |
| `make test-elisp` | Emacs major-mode ERT tests |
| `make test-bootstrap` | Clean bootstrap and fixed-point comparison |

If a CUDA prerequisite is not available, the `test-gpu` target skips the test.

The `test-reference-parity` target requires Python and pytest. The `test-elisp` target requires Emacs and builds the compiler stages first.

See [tests/README.md](tests/README.md). It describes the compiler test suites.

To run all available test groups, run:

```bash
make test-bootstrap test test-gpu test-reference-parity test-elisp
```
