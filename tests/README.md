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
- **Pascal fixture format**: Put directive comments in a `.pas` file. Use `{ CHECK: text }`, `{ CHECK-NOT: text }`, or `{ CHECK-COUNT: N text }`. Use `{ CHECK-ENV: NAME=value }` to set a codegen environment variable.
- **Frozen AST format**: A `.check` file can use `{ CHECK-INPUT: path.json }`. The runner sends that typed AST to native codegen. Sources and frozen Python reference ASTs are in `tests/reference/codegen/`.
- **Artifact updates**: Run `PYTHONPATH=. ./scripts/update-reference-codegen.sh`. Review all JSON changes before you commit them. Routine tests do not run this Python-based maintenance command.
- **Running**:
  ```bash
  ./tests/checklit.sh
  ```

### 5. Pre-Commit Hook Test Suite (`tests/test_precommit_hook.sh`)

- **Runner**: [`tests/test_precommit_hook.sh`](./test_precommit_hook.sh)
- **Description**: Checks hook restaging, partial staging, tool errors, optional tools, and the executable file mode. Each behavior test uses an isolated Git repository.
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
