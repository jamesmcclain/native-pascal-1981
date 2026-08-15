# Test Suites for `native-pascal-1981`

This directory contains the automated test suites for the native Pascal 1981 compiler toolchain.

## Overview of Test Suites

### 1. Golden-File Test Suite (`tests/golden/`)
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

### 2. Parity Test Suite (`tests/parity/`)
- **Runner**: `pytest`
- **Description**: Comprehensive parity test suite comparing native compiler stages (`lexer`, `parser`, `typechecker`, `codegen`) against the Python reference compiler (`pascal1981`), including AST equivalence, code generation, record layouts, deep recursion limits, and device/kernel launches.
- **Running**:
  ```bash
  PYTHONPATH=. pytest tests/parity/
  ```

---

## Running All Tests

You can run both test suites together via the top-level `Makefile`:

```bash
make test
```
