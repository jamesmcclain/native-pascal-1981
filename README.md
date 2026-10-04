# Native Pascal 1981 Compiler

This repository contains a native compiler for the 1981 IBM Pascal dialect. It targets LLVM IR, the System V AMD64 ABI, and NVIDIA NVPTX.

**Compatibility rule: fun, not pathology.** Follow the IBM manual where it
preserves the language's character, not where historical machine constraints
make modern behavior needlessly pathological. Deliberate differences must be
documented and tested. For example, native `INTEGER` accepts the full signed
16-bit range, including `-32768` in both dialects; INITCK uses separate shadow
state, never a reserved program-data sentinel. Host enforcement covers supported
scalar locals/formals/results, fixed aggregates, typed pointers and tracked
NEW/SUPER ARRAY storage, with explicit external/raw/file/DEVICE boundaries.
It is not whole-program protection: globals, untracked types and aggregate
results remain outside the checked slice. See the
[INITCK contract and limits](docs/dialect_notes.md#initialization-checking-host-storage-native).

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

The build needs no Python and no other Pascal compiler. Some optional test
groups need more; see [Running Tests](#running-tests).

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
- `bootstrap/`: `pasboot`, a C99 translator from the bootstrap subset of the dialect to C. It builds Generation 1 of the compiler stages. [`docs/bootstrap_subset.md`](docs/bootstrap_subset.md) defines the subset.
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
1. **Generation 1 (Bootstrap)**: Builds `bootstrap/pasboot`. Then `pasboot` translates each compiler-stage compiland to C, and `clang` compiles it. The Generation 1 sources must stay inside the [bootstrap subset](docs/bootstrap_subset.md).
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
- `--dialect <vintage|extended>`: Select the language dialect (default `vintage`)
- `--target-cpu <cpu>`: Host target CPU, e.g. `x86-64-v3` (LLVM `target-cpu` attribute; default baseline x86-64)
- `--target-features <list>`: Host target features, comma-separated, e.g. `+avx2,+fma`
- `--emit-ptx`: Emit NVPTX assembly for device kernels
- `-v`: Print pipeline commands

## Running Tests

Run the routine test suites:

```bash
make test
```

This target runs the bootstrap-subset check, the `pasboot` fixtures, and the driver, sysutil, native, proxy, and pre-commit-hook test groups. The test runners do not require pytest. The proxy tests need `python3`.

This target does not run the bootstrap or Emacs tests.

Use these targets for a specific test group:

| Target | Test group |
| --- | --- |
| `make check-bootstrap-subset` | Generation 1 sources stay inside the bootstrap subset. No Python needed. |
| `make test-pasboot` | Per-feature fixtures for the `pasboot` bootstrap translator. No Python needed. |
| `make test-driver` | Driver, golden-file, and IR/PTX-text directive tests. No Python needed. |
| `make test-native` | Routine native compiler tests |
| `make test-sysutil` | POSIX filesystem and process primitives, exercised from Pascal |
| `make test-proxy` | Differential conformance for the completion proxy (needs `python3`) |
| `make test-gpu` | CUDA compilation and execution on an NVIDIA GPU |
| `make test-elisp` | Emacs major-mode ERT tests |
| `make test-bootstrap` | Clean bootstrap and fixed-point comparison, with Python made unavailable |

If a CUDA prerequisite is not available, the `test-gpu` target skips the test.

The native compiler is the authoritative implementation. A parity suite comparing it with an earlier Python implementation remains in `tests/parity/` but is disabled and slated for removal; see [tests/README.md](tests/README.md) if you need it. The `test-elisp` target requires Emacs and builds the compiler stages first.

See [tests/README.md](tests/README.md). It describes the compiler test suites.

To run all available test groups, run:

```bash
make test-bootstrap test test-gpu test-elisp
```
