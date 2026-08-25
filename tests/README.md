# Test Suites for `native-pascal-1981`

This directory contains the automated test suites for the native Pascal 1981 compiler toolchain.

## Overview of Test Suites

### 1. Driver Contract Test Suite (`tests/driver.sh`)
- **Runner**: [`tests/driver.sh`](./driver.sh)
- **Description**: Checks the public driver CLI without a bootstrap build. The runner uses temporary stage programs to check option errors, missing sources and stages, failed stages and `clang`, literal source and output paths, default IR output, and multi-file linking.
- **Running**:
  ```bash
  make test-driver
  ```

### 2. Golden-File Test Suite (`tests/golden/`)
- **Runner**: [`tests/run.sh`](./run.sh)
- **Description**: Fast, end-to-end integration tests using the native driver binary (`bin/pascal1981-native`). Each test is compiled and executed, verifying exit codes, standard output, and standard error against expected golden files (`.out`, `.err`, `.exitcode`).
- **Running**:
  ```bash
  ./tests/run.sh
  ```
  To run with parallel worker jobs:
  ```bash
  ./tests/run.sh -j 4
  ```

### 3. Parity Test Suite (`tests/parity/`)
- **Runner**: `pytest`
- **Description**: Comprehensive parity test suite comparing native compiler stages (`lexer`, `parser`, `typechecker`, `codegen`) against the Python reference compiler (`pascal1981`), including AST equivalence, code generation, record layouts, deep recursion limits, and device/kernel launches.
- **Running**:
  ```bash
  PYTHONPATH=. pytest tests/parity/
  ```
- **Why this stays Python-based**: this suite's job is to diff native output against the Python reference compiler as the correctness oracle. That comparison is a semantic requirement, not a legacy shortcut -- a Python-free tool can't perform it without reimplementing the reference compiler. Contrast with the checklit suite below.

### 4. Checklit Directive Suite (`tests/checklit/)`
- **Runner**: [`tests/checklit.sh`](./checklit.sh)
- **Description**: Makes zero-Python assertions on emitted LLVM IR or PTX text. The runner supports required, forbidden, and counted substrings. It does not enforce check order.
- **Pascal fixture format**: Put directive comments in a `.pas` file. Use `{ CHECK: text }`, `{ CHECK-NOT: text }`, or `{ CHECK-COUNT: N text }`. Use `{ CHECK-ANY: text || alternative }` when LLVM versions use different text for the same contract. Use `{ CHECK-ENV: NAME=value }` to set a codegen environment variable.
- **Frozen AST format**: A `.check` file can use `{ CHECK-INPUT: path.json }`. The runner sends that typed AST to native codegen. Sources and frozen Python reference ASTs are in `tests/reference/codegen/`.
- **Artifact updates**: Run `PYTHONPATH=. ./scripts/update-reference-codegen.sh`. Review all JSON changes before you commit them. Routine tests do not run this Python-based maintenance command.
- **Running**:
  ```bash
  ./tests/checklit.sh
  ```

### 5. Native Depth Test Suite (`tests/depth.sh`)

- **Runner**: [`tests/depth.sh`](./depth.sh)
- **Description**: Checks expression, statement, and type nesting boundaries in the native parser. It checks depth unwinding between sibling expressions. It also sends frozen oversized ASTs to the native typechecker and code generator. Bounded tests use a five-second timeout; parser and typechecker tests also use a 128 MiB address-space limit.
- **Artifact updates**: Run `PYTHONPATH=. ./scripts/update-reference-depth.py`. Review changes under `tests/reference/depth/` before you commit them. Routine tests do not run this maintenance command.
- **Running**:
  ```bash
  ./tests/depth.sh
  ```

### 6. Native JSON Comparator Suite (`tests/astcompare.sh`)

- **Runner**: [`tests/astcompare.sh`](./astcompare.sh)
- **Tool**: `bin/astcompare`
- **Description**: Checks structural JSON comparison without Python. Object keys are unordered, arrays are ordered, and `--ignore-key KEY` applies recursively. Mismatches report a JSON path. The suite also compares native parser and typechecker output with frozen Python-reference ASTs. Typed comparisons ignore the output-only `resolved_type` field.
- **Artifact updates**: Run `./scripts/update-reference-ast.sh`. Review the Pascal sources and JSON under `tests/reference/ast/` before you commit changes. Routine tests do not run this Python-based maintenance command.
- **Running**:
  ```bash
  ./tests/astcompare.sh
  ```

### 7. GPU Orchestration Suite (`tests/gpu_orchestration.sh`)

- **Runner**: [`tests/gpu_orchestration.sh`](./gpu_orchestration.sh)
- **Description**: Compiles and runs vector addition with the CUDA backend. The runner uses frozen typed ASTs from the independent Python front end. It checks each GPU and CUDA prerequisite. It prints one skip reason if a prerequisite is not available.
- **Artifact updates**: Run `./scripts/update-reference-gpu.sh`. Review the Pascal sources and typed ASTs under `tests/gpu/` before you commit changes.
- **Running**:
  ```bash
  make test-gpu
  ```

### 8. Pre-Commit Hook Test Suite (`tests/test_precommit_hook.sh`)

- **Runner**: [`tests/test_precommit_hook.sh`](./test_precommit_hook.sh)
- **Description**: Checks hook restaging, partial staging, tool errors, optional tools, and the executable file mode. Each behavior test uses an isolated Git repository.
- **Requirements**: Install `isort` and `yapf`. The runner names missing formatters and fails before it starts the tests.
- **Running**:
  ```bash
  ./tests/test_precommit_hook.sh
  ```

---

## Running the Routine Tests

Run the routine compiler and hook tests:

```bash
make test
```

This target does not require pytest. It does not run the reference-parity suite.

Run the Python reference-parity suite separately:

```bash
make test-reference-parity
```
