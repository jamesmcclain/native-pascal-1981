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

> **GPU kernels must use `{$MATHCK-}` for integer arithmetic.** Integer
> overflow checking (`$MATHCK`) is on by default, and NVPTX code has no way to
> report a run-time error. So in DEVICE code compiled for NVPTX, every integer
> operation MATHCK would check (`+ - * DIV MOD`, unary `-`, `SUCC`, `PRED`,
> `ABS`, `SQR`) is a compile-time error,
> `MATHCK unsupported boundary: DEVICE arithmetic at line L column C`, until
> the kernel says `{$MATHCK-}`. That arithmetic is then unchecked and wraps.
> CPU (serial) DEVICE code is checked like host code. See
> [GPU kernels and `$MATHCK`](docs/dialect_notes.md#gpu-nvptx-kernels-need-mathck--for-integer-arithmetic-extended).

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

## Temporary files

The [temporary-file ownership contract](docs/temporary_files.md) is the
canonical guide to scratch isolation and cleanup for the compiler, runtime,
test harnesses, and Emacs mode. Read it before changing temporary-file handling
or manually removing abandoned workspaces.

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
- `--emit-ptx`: Emit NVPTX assembly for device kernels (kernels doing integer arithmetic need `{$MATHCK-}`; see above)
- `-v`: Print pipeline commands

## Running Tests

Run the routine test suites:

```bash
make test
```

Every suite is a script in a tier directory under `tests/`, grouped by what
it does mechanically:

| Tier | What its suites do |
| --- | --- |
| `tests/check/` | Static checks: generation 1 stays inside the bootstrap subset; the pre-commit hook and formatter; the suite index in `tests/README.md` is current. |
| `tests/unit/` | Runtime C unit tests, `pasboot` fixtures, the test launcher. |
| `tests/corpus/` | Fixture corpora compiled and compared with expected output: golden programs, IR directives, depth limits, AST comparison. |
| `tests/contract/` | Scripted checks of compiler, driver and runtime behavior (MATHCK, INITCK, INDEXCK, descriptors, stage CLIs, ...). |
| `tests/service/` | The completion proxy against a deterministic stub backend (needs `python3`). |
| `tests/optional/` | Opt-in: CUDA hardware, overhead measurements. Never run by `make test`. |

`make test` runs the `check` and `unit` tiers first (they need no
bootstrap), then builds every tool and runs the `corpus`, `contract` and
`service` tiers. Suites run in parallel, longest first. It runs every suite
even after one fails, and ends with a summary of failed suites with their
`FAIL` lines, and of suites that skipped checks; each suite's full output is
kept in `build/test-results/<suite>.log`. `make test-quick` runs only the
first two tiers, in seconds.

To run some suites, name tiers or suites, or run a suite script directly
(from any directory; it sets up the same environment itself):

```bash
make test SUITES="contract depth"
./tests/contract/mathck_vector.sh
```

The test runners do not require pytest. The proxy tests need `python3`.

Install bubblewrap (`bwrap`; the `bubblewrap` package on Debian or Ubuntu) as
well. The temporary-directory safety test runs its cases in a `bwrap`
sandbox with a private `/tmp`; without `bwrap` that test is skipped rather
than failed, so `make test` passes with less coverage. The summary lists it
among the suites that skipped checks.

These targets are separate from `make test`:

| Target | Test group |
| --- | --- |
| `make test-gpu` | CUDA compilation and execution on an NVIDIA GPU |
| `make test-elisp` | Emacs major-mode ERT tests |
| `make test-bootstrap` | Clean bootstrap and fixed-point comparison, with Python made unavailable |

If a CUDA prerequisite is not available, the `test-gpu` target skips the test.

The native compiler is the authoritative implementation; no test compares it with the earlier Python implementation. The `test-elisp` target requires Emacs and builds the compiler stages first.

See [tests/README.md](tests/README.md). It describes the compiler test suites. Before adding or changing a test, read [docs/test_portability.md](docs/test_portability.md): the suites must not depend on a quiet compiler, particular bash/make/LLVM versions, or optional tools.

To run all available test groups, run (`test-bootstrap` deletes `build/`, so
it must run on its own):

```bash
make test-bootstrap
make test test-gpu test-elisp
```
