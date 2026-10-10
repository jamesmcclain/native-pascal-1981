# Host descriptor contract tests

The descriptor transport, boundary, NEW and index probes. The test suites themselves are described in
[tests/README.md](../../tests/README.md).

## Host descriptor contracts

- [Transport and boundary probes](#descriptor-transport-and-boundary-probes)
- [NEW and index probes](#descriptor-new-and-index-probes)
- [Host ABI contract](../dialect_notes.md#host-super-array-descriptor-abi-native)

### Descriptor transport and boundary probes

```sh
make test SUITES=descriptor_contract
# With current driver, runtime and bin/ stages already built:
./tests/contract/descriptor_contract.sh
```

The Make target installs rebuilt stages and is included in `make test`.
The script reports failures and exits nonzero on any failure; there are no XFAILs
or expected-red success mode. Negative fixtures compile only (`-S`): undefined
EXTERN symbols cannot substitute for compiler rejection, and invalid raw pointers
or DEVICE launches are not executed. Exact new compile diagnostic wording is not
pinned: rejections require boundary-related diagnostics, not parser/name errors.

Inputs below are under `tests/contract/descriptor/` unless otherwise named:

| Input / assertion family | Coverage |
| --- | --- |
| `transport.pas` / `.out` | Two allocation sizes at lower 2, variable/type aliases retain bounds after replacement, selected record/array slots, reads/writes, value/VAR (including selected actuals), pointer/record results, once-only calls/indexes, NIL assignment/arguments/equality; each allocation freed once. IR pins globals/aggregate slots, whole load/store and NEW/NIL publication, two-piece value/result and VAR-slot ABI, matching calls, no pre-data lookup/free. |
| `layout.pas` / `.out` | Descriptor and one-field record size 16, two-element descriptor array size 32. |
| `aggregate_abi.pas` | 32-byte descriptor pair uses SysV MEMORY/byval and sret, matching call attributes; sret pattern accepts preceding required `noalias`. |
| `register_budget.pas` / `.out` | After five GP arguments a descriptor rolls back wholly to byval, leaving a GP register for the trailing scalar; hidden sret consumes a GP register. RETURN does not append an epilogue after a terminated block. |
| `tests/corpus/integration/descriptor_units.*` | Separately compiled unit/program agree on exported globals, native value/result and selected VAR-slot ABI, not merely an in-module match. |
| `tests/corpus/golden/descriptor_unsafe*.pas` | Explicit import/export bounds and side-effect counts, selected UPPER of import, equality-by-data with differing upper, NIL raw printing, exact native free base and builtin shadowing. Compiler warnings checked separately from stdout, no ownership inference. |
| `tests/corpus/golden/descriptor_word_domain.pas`, `tests/corpus/golden/descriptor_ordinal_domains.pas` | WORD/CHAR/BOOLEAN/enum domains, full-width bounds and unsigned element offsets. |
| `unsafe_failures.pas` | Exact nonreturning runtime diagnostics before sentinel output under INDEXCK-: lower mismatch, WORD64 overflow, NIL, misalignment, upper below lower/outside domain. `tests/contract/fixtures/super_import_runtime.c` independently tests valid metadata, byte-span/address overflow and wide unsigned bounds without dereferencing addresses. |
| `reject_*.pas` | Implicit CPTR/thin/different-lower/nominal conversions; arithmetic/RETYPE/numeric I/O/slot ADR; pointer/aggregate-result argument mismatches; recursive C value/VAR/result/variadic/aggregate and known typed address paths; LAUNCH/DEVCOPY; invalid unsafe type/raw/bounds; deferred borrowed formals. |
| `device_thin.pas`, `device_interface_thin.pas` | Thin host/CPU-device/NVPTX DEVICE parameters and spliced interface storage after host-state restoration. These compile/IR probes do not require a GPU execution claim. |
| `foreign_recursive_thin.pas`, `reject_device_host_abi.pas`, `device_host_raw_interface.pas` | Ordinary recursive thin C signatures remain accepted; imported host descriptors rejected in DEVICE; opaque raw-only APIs survive a private unused host descriptor type. |
| `tests/corpus/dialect/vintage_unsafe_conversion.pas` | Unsafe syntax is extended-only. |

Runtime goldens are explicitly passed to `tests/corpus/fixtures.sh`; automatic discovery does
not collect this directory's compile-only inputs. `DESCRIPTOR_DRIVER` selects an
alternate IR compiler only: runtime goldens retain the normal native runner driver.
The suite requires the C compiler/runtime archive for independent import tests.
Expectations pin descriptor layout, not the old thin-pointer representation;
implementation chronology and old red transcripts are not the current contract.

### Descriptor NEW and index probes

`tests/contract/super_new_contract.sh` (in `make test`)
checks:

- Two valid and ten failing independent runtime arithmetic/allocation cases.
- Six selected-slot failure cases with test-only malloc/abort/free linker wrappers,
  exact diagnostics and once-only selection/bound counts; bound-expression side
  effects are not rolled back. No production allocator test hook.
- Huge source byte-size overflow under INDEXCK-, wide strides, whole publication
  IR, successful rebinding/alias retention, aligned vectors and exact free bases.
- `tests/contract/descriptor/reject_new_*.pas`: overflowing static layouts, unsupported
  record offsets and over-alignment; huge allocations are never executed.

`tests/corpus/golden/indexck_super_*` plus descriptor-upper probes in
`tests/contract/indexck_guard_ir.sh` cover endpoints, below/above, wide unsigned/negative
indexes, executed/dead constant bad indexes, once-only evaluation and per-slot
actual uppers. `tests/contract/indexck_diagnostics.sh` pins the first index-token
line/column for fixed/SUPER loads and stores in both dialects at O0–O3,
including legacy `0:0` coordinates and nested-index snapshots.
`indexck_super_nil_*` covers NIL load/store/selected record fields;
IR probes pin snapshots and guard-free disabled super subscripts. Index side-effect
ordering before NIL failure is deliberately not pinned down. Borrowed views and
temporal safety remain unsupported; the suite never executes invalid unchecked
scalar accesses. Related `tests/contract/indexck_metadata.sh`, `bound_expression_*` goldens
and `tests/contract/driver.sh` preserve bounds evaluation and driver routing. Native
checklit/depth/stage/AST suites are broader gates, not substitutes for these probes.
