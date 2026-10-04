# Host SUPER ARRAY descriptor contract probes

The first transport implementation milestone for
[the host ABI](../../docs/host_super_array_abi.md) now passes these contracts:

```sh
make test-descriptor-contract
# or, with current bin/ stages already installed:
bash tests/descriptor_contract.sh
```

The target installs the rebuilt stages used by the driver and is included in
`make test-native`. No XFAILs or expected-red success mode. The script reports all
failed assertions and returns nonzero on any failure. Negative fixtures are
compile-only (`-S`): undefined EXTERN symbols never substitute for a real compiler
rejection, and invalid raw pointers or DEVICE launches are never executed.

## Coverage

- `transport.pas` / `.out`: two allocation sizes at lower 2; variable/type aliases
  retaining bounds after pointer replacement; selected record and array slots;
  reads/writes, value/VAR parameters (including selected actual slots), pointer
  and record results; once-only selected call/index evaluation; NIL arguments,
  assignments and equality. Frees each allocation once.
- `layout.pas` / `.out`: descriptor size 16, single-field record size 16 and
  two-element descriptor array size 32.
- IR checks on `transport.pas`: descriptor globals/aggregate slots, full-value
  load/store and NEW/NIL publication, two-piece value/VAR/result native ABI,
  matching calls and no host pre-data header lookup/free.
- `aggregate_abi.pas`: 32-byte two-descriptor record needs SysV MEMORY/byval
  parameters and sret results, including call-site attributes. The sret call
  assertion accepts the required `noalias` attribute preceding `sret`.
- `register_budget.pas` / `.out`: after five GP arguments a descriptor must roll
  back entirely to byval, leaving the remaining GP register for a trailing
  scalar. An sret hidden pointer consumes a GP register too. Explicit RETURN
  must not append an epilogue after a terminated block.
- `tests/integration/descriptor_units.*`: separately compiled unit and program
  agree on exported descriptor globals, native value/result ABI and selected
  VAR-slot passing. This is not just an in-module caller/callee agreement.
- `tests/golden/descriptor_unsafe*.pas`: explicit unsafe export/import, supplied
  bounds, side-effect counts, selected UPPER of an import, equality-by-data even
  with different upper bounds, NIL raw printing, exact native free base and
  normal intrinsic shadowing. Compiler warnings are checked separately from
  runtime stdout; no claim of ownership inference.
- `descriptor_word_domain.pas` and `descriptor_ordinal_domains.pas`: declared
  WORD/CHAR/BOOLEAN/enum domains, full-width bounds and unsigned element offsets.
- `unsafe_failures.pas`: exact nonreturning diagnostics for mismatched lower,
  WORD64 bound overflow, NIL data, misalignment, upper below lower and an upper
  outside the declared domain, all under INDEXCK- and before the following
  sentinel output. `tests/super_import_runtime.c` independently exercises byte-
  span/address overflow, wide unsigned lower/upper and valid metadata, without
  dereferencing supplied addresses.
- `reject_*.pas`: implicit CPTR/thin-pointer/different-lower/nominal conversions,
  arithmetic, RETYPE, numeric descriptor I/O, slot ADR escape, pointer- and
  aggregate-result argument mismatch, C value/VAR/result/variadic/aggregate
  signatures and known typed address paths (including recursive records),
  LAUNCH/DEVCOPY, unsafe imports lacking valid type/raw/bounds and deferred
  borrowed formals. Rejections need a boundary-related diagnostic; parser/name
  errors do not count. Exact new compile diagnostic wording is not pinned.
- `device_thin.pas`: host/CPU-device and NVPTX keep thin DEVICE parameters.
  `device_interface_thin.pas` checks that a spliced DEVICE interface remains thin
  after restoring host compilation state. `foreign_recursive_thin.pas` protects
  ordinary recursive thin-pointer C signatures from overbroad rejection.
  `reject_device_host_abi.pas` rejects imported native host descriptor signatures
  in DEVICE code; `device_host_raw_interface.pas` preserves opaque raw-only APIs
  even when their host interface declares a private, unused descriptor type.
- `tests/dialect/vintage_unsafe_conversion.pas`: unsafe syntax is extended-only.

Runtime goldens use `tests/run.sh` explicitly; automatic collection still skips
this directory's compile-only fixtures. `DESCRIPTOR_DRIVER` may select an alternate
IR compiler, but runtime goldens use the normal native runner's driver. The suite
requires the C compiler/runtime archive for independent import arithmetic tests.

## Historical red baseline

At `e857c95` plus the original fixtures (`3f61ecf`), behavior transport passed,
but layout printed `8 8 16`; IR stored thin pointers, returned `ptr`, treated the
two-pointer record as a register aggregate and used data-8 headers. All eleven
original rejection fixtures compiled. The original script reported 30 failures
out of 38 checks and exited 1. Expectations were not weakened to match thin
pointers; only the sret attribute-order pattern was corrected when valid IR
exposed the original probe's omission of `noalias`.

`make test-super-new` / `tests/super_new_contract.sh` now cover hardened NEW:
- two valid and ten failing independent runtime arithmetic/allocation cases;
- six selected-slot failure cases with test-only malloc/abort/free linker wrappers,
  exact diagnostics and once-only bound/selection counts, including bound-expression
  side effects (which are deliberately not rolled back);
- source-level huge byte-size overflow under INDEXCK-, wide allocation strides,
  whole-value publication IR, successful rebinding/alias retention and aligned
  vector elements; frees remain exact original data bases;
- `reject_new_*.pas` reject overflowing static element layouts, unsupported large
  record offsets and over-aligned elements, without executing huge allocations.

Scalar checked-index failures of host super-array subscripts are implemented and
tested by the `indexck_super_*` goldens plus the descriptor-upper IR probes in
`tests/indexck_guard_ir.sh`: endpoints, below/above bounds, wide unsigned and
negative indexes, executed and dead constant bad indexes, once-only index
evaluation and per-slot actual uppers. Checked NIL indexing is implemented and
tested by the `indexck_super_nil_*` goldens (load, store and a selected record
field), with `$INDEXCK` snapshot and guard-free-IR probes for super subscripts
in `tests/indexck_guard_ir.sh`; whether an index expression's side effects run
before the NIL failure is deliberately not pinned down. Borrowed views and
temporal safety
remain later punchlist milestones. No invalid
unchecked scalar access is executed by this suite.
