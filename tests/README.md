# Test Suites for `native-pascal-1981`

This directory contains the automated test suites for the native Pascal 1981 compiler toolchain.

## Overview of Test Suites

### 1. Driver Contract Test Suite (`tests/driver.sh`)
- **Runner**: [`tests/driver.sh`](./driver.sh)
- **Description**: Checks the public driver CLI without a bootstrap build. The runner uses temporary stage programs to check option errors, stage failures, and literal source and output paths.
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

### 4. Checklit Directive Suite (`tests/checklit/)
- **Runner**: [`tests/checklit.sh`](./checklit.sh)
- **Description**: Zero-dependency, zero-Python assertions on emitted LLVM IR / PTX text, in the spirit of LLVM's `lit`/`FileCheck` but minimal (unordered substring matching, no DAG/COUNT vocabulary). This is the native-runner path for the class of test that otherwise lives only in `tests/parity/` as a Python string assertion on codegen output (kernel launch ABI, attribute placement, PTX directives) -- coverage that doesn't need the Python reference as an oracle, it just needs to inspect what native codegen emitted. New coverage of that shape can go here without adding a Python dependency; existing `tests/parity/` coverage of the same shape hasn't been migrated away, to avoid losing anything mid-transition.
- **Fixture format**: a `.pas` file with `{ CHECK: <substring> }` directive comments (and optional `{ CHECK-ENV: NAME=value }` for codegen env vars like `PASCAL_EMIT_PTX=1`); see `tests/checklit/byval_c_aggregate.pas`.
- **Running**:
  ```bash
  ./tests/checklit.sh
  ```

---

## Running All Tests

You can run all three test suites together via the top-level `Makefile`:

```bash
make test
```
