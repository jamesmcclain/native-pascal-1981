# Native Pascal 1981 Compiler

This repository contains a native compiler for the 1981 IBM Pascal dialect. It targets LLVM IR, the System V AMD64 ABI, and NVIDIA NVPTX.

<img width="1536" height="864" alt="image" src="https://github.com/user-attachments/assets/f59a2d0f-468b-41b2-838c-b76729f15975" />

## System Prerequisites

Install these packages before you build the toolchain (for example, on Debian or Ubuntu Linux x86_64):

- `clang` (C compiler and linker)
- `make` (build tool)
- `libllvm-20-dev` / `llvm-20` (LLVM 20 library and headers)
- `libcjson-dev` (cJSON library and headers)
- `indent` (C code formatting tool)
- `python3` and `pip3` with the reference compiler package:
  ```bash
  pip3 install 'https://github.com/jamesmcclain/pascal-1981/archive/99a8f3f4b4f5259a43301c9b8879f3fc891d3503.zip'
  ```

## Repository Layout

- `src/`: Native compiler stages and driver in Pascal (`lexer.pas`, `parser.pas`, `typechecker.pas`, `codegen.pas`, `driver.pas`, `jsonutil.pas`, `jsonutil.inc`). The codegen stage is a composition root over eight separately compiled units, each a `.inc` interface plus a `.pas` implementation, layered lowest first and only ever depending downward:
  - `cg_base`: shared compiler state, LLVM-C and libc prototypes, constants and record types.
  - `cg_util`: diagnostics, depth guards, string and pointer-array helpers.
  - `cg_types`: the type registry, sizing and layout, constant folding, SysV classification.
  - `cg_symbols`: symbol, scope and routine tables.
  - `cg_expr`, `cg_io`, `cg_stmt`, `cg_decl`: the four lowering layers (expressions, WRITE/READ, statements, declarations).
- `runtime/`: C runtime static library and headers (`libpascalrt.a`, `pascalrt.h`).
- `bin/`: Compiler driver (`pascal1981-native`, alias `pascal1981`) and stage binaries (`lexer`, `parser`, `typechecker`, `codegen`).
- `scripts/`: Build scripts (`build-stage.sh`), formatting scripts (`beautify.sh`), and git hooks (run `git config core.hooksPath scripts/hooks` once per clone to enable the pre-commit formatting hook — it's local config, so a fresh checkout won't run it until you do). The multi-generation bootstrap itself is driven by the root `Makefile`'s `bootstrap` target, not a standalone script.
- `tests/`: Test suites (golden files, unit tests, integration tests, dialect fixtures).

## Building

To build the runtime, driver, and bootstrap all compiler stages:
```bash
make
```

By default, the build uses `llvm-config` (or `llvm-config-20` if `llvm-config` is not in PATH) to dynamically determine LLVM linker flags and libraries. You can explicitly override this by setting `LLVM_CONFIG`:
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

The bootstrap process is composed of four steps:
1. **Generation 1 (Hybrid)**: Builds the native compiler stages with the Python reference compiler (`pascal1981`).
2. **Generation 2 (Self-hosted)**: Recompiles all native compiler stages with the Generation 1 binaries.
3. **Generation 3 (Self-hosted)**: Recompiles all native compiler stages with the Generation 2 binaries.
4. **Generation 4 (Fixed Point)**: Recompiles all native compiler stages with the Generation 3 binaries and verifies binary identity (`cmp`). `make driver` then compiles `src/driver.pas` with those stages and installs it as `bin/pascal1981-native` (with `bin/pascal1981` as its alias).

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

This target runs the driver, native, checklit, and pre-commit-hook tests. The test runners do not require pytest.

This target does not run the reference-parity, bootstrap, or Emacs tests.

Use these targets for a specific test group:

| Target | Test group |
| --- | --- |
| `make test-driver` | Driver command-line behavior |
| `make test-native` | Routine native compiler tests |
| `make test-gpu` | CUDA compilation and execution on an NVIDIA GPU |
| `make test-reference-parity` | Native compiler parity with the Python reference compiler |
| `make test-elisp` | Emacs major-mode ERT tests |
| `make test-bootstrap` | Clean bootstrap and fixed-point comparison |

The `test-gpu` target skips the test if a CUDA prerequisite is not available.

The `test-reference-parity` target requires Python and pytest. The `test-elisp` target requires Emacs and builds the compiler stages first.

See [tests/README.md](tests/README.md) for more information about the compiler test suites.
