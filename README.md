# Native Pascal 1981 Compiler (`native-pascal-1981`)

A standalone, self-hosting native compiler for the vintage 1981 IBM Pascal dialect with modern backend targets (LLVM IR, System V AMD64 ABI, and NVIDIA NVPTX).

## System Prerequisites

To build, bootstrap, and run the native compiler toolchain, the following packages must be installed on your system (e.g. Debian/Ubuntu Linux x86_64):

- `clang` (C compiler and linker driver)
- `make` (GNU Make build tool)
- `libllvm-20-dev` / `llvm-20` (LLVM 20 C API library and headers)
- `libcjson-dev` (cJSON AST transport library and headers)
- `indent` (GNU indent for C code formatting)
- `python3` / `pip3` with the Python reference compiler installed (required for the initial Generation 1 bootstrap):
  ```bash
  pip3 install https://github.com/jamesmcclain/pascal-1981/archive/c911ca7dbac51ce10799873979420c8edbe10c6a.zip
  ```

## Repository Layout

- `src/`: Native compiler stages written in Pascal (`lexer.pas`, `parser.pas`, `typechecker.pas`, `codegen.pas`, `jsonutil.pas`, `jsonutil.inc`).
- `runtime/`: C runtime static library `libpascalrt.a` and headers (`pascalrt.h`).
- `driver/`: Native compiler driver implementation in C (`main.c`).
- `bin/`: Installed compiler driver (`pascal1981-native`, alias `pascal1981`) and native stage binaries (`lexer`, `parser`, `typechecker`, `codegen`).
- `scripts/`: Stage build (`build-stage.sh`), multi-generational bootstrap (`bootstrap.sh`), formatting (`beautify.sh`), and git hooks.
- `tests/`: Test suites (golden-file tests, unit tests, integration tests, dialect fixtures).

## Building & Bootstrapping

### 1. Build Runtime & Compiler Driver
```bash
make
```

### 2. Multi-Generational Bootstrap & Fixed-Point Verification
```bash
make bootstrap
```
This runs `scripts/bootstrap.sh`, which performs:
1. **Generation 1 (Hybrid)**: Builds native compiler stages using the Python reference compiler (`pascal1981`).
2. **Generation 2 (Self-hosted)**: Recompiles all native stages using the Gen 1 binaries.
3. **Generation 3 & 4 (Fixed Point)**: Recompiles stages with Gen 2 and Gen 3 binaries, verifying byte-for-byte binary fixed point (`cmp gen3 gen4`), and installs the verified binaries to `bin/`.

### 3. Compiling Programs with the Native Compiler
```bash
bin/pascal1981-native hello.pas -o hello
./hello
```
Supported flags:
- `-o <file>`: Output path
- `-c`: Compile to object file (`.o`)
- `-S`: Compile to LLVM IR (`.ll`)
- `-O0`, `-O1`, `-O2`, `-O3`: Optimization level
- `--emit-ptx`: Emit NVPTX assembly for device kernels
- `-v`: Verbose pipeline commands
