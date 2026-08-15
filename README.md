# Native Pascal 1981 Compiler (`native-pascal-1981`)

This repository contains a native compiler for the 1981 IBM Pascal dialect. It targets LLVM IR, the System V AMD64 ABI, and NVIDIA NVPTX.

## System Prerequisites

Install these packages before you build the toolchain (for example, on Debian or Ubuntu Linux x86_64):

- `clang` (C compiler and linker)
- `make` (build tool)
- `libllvm-20-dev` / `llvm-20` (LLVM 20 library and headers)
- `libcjson-dev` (cJSON library and headers)
- `indent` (C code formatting tool)
- `python3` and `pip3` with the reference compiler package:
  ```bash
  pip3 install https://github.com/jamesmcclain/pascal-1981/archive/c911ca7dbac51ce10799873979420c8edbe10c6a.zip
  ```

## Repository Layout

- `src/`: Native compiler stages in Pascal (`lexer.pas`, `parser.pas`, `typechecker.pas`, `codegen.pas`, `jsonutil.pas`, `jsonutil.inc`).
- `runtime/`: C runtime static library and headers (`libpascalrt.a`, `pascalrt.h`).
- `driver/`: Native compiler driver in C (`main.c`).
- `bin/`: Compiler driver (`pascal1981-native`, alias `pascal1981`) and stage binaries (`lexer`, `parser`, `typechecker`, `codegen`).
- `scripts/`: Build scripts (`build-stage.sh`), bootstrap scripts (`bootstrap.sh`), formatting scripts (`beautify.sh`), and git hooks.
- `tests/`: Test suites (golden files, unit tests, integration tests, dialect fixtures).

## Building and Bootstrapping

### 1. Build the Runtime and Driver
```bash
make
```

### 2. Bootstrap the Toolchain
To build and verify the compiler stages, run:
```bash
make bootstrap
```
The bootstrap script executes four steps:
1. **Generation 1 (Hybrid)**: Builds the native compiler stages with the Python reference compiler (`pascal1981`).
2. **Generation 2 (Self-hosted)**: Recompiles all native compiler stages with the Generation 1 binaries.
3. **Generation 3 (Self-hosted)**: Recompiles all native compiler stages with the Generation 2 binaries.
4. **Generation 4 (Fixed Point)**: Recompiles all native compiler stages with the Generation 3 binaries, verifies binary identity (`cmp`), and installs the binaries to `bin/`.

### 3. Compile a Program
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
