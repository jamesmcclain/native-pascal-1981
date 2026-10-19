# NILCK: null-only ordinary host pointer dereferences

## Adopted first slice

NILCK defaults on. An ordinary host typed-pointer `^` consumes the boolean
`NILCK` in that selector's `read_flags`, captured at the `^` token (including
WITH targets), not at the declaration, root identifier or later statement.
Legacy/malformed/missing snapshots are unchecked, matching INITCK's policy;
missing coordinates with an enabled snapshot report line 0 column 0.
Typechecking preserves the selector snapshots.

The shared designator-address walk evaluates each pointer once, performs any
supported INITCK guard before loading pointer bits, then tests the loaded
pointer for null before heap-shadow lookup, pointer-derived GEP, pointee
load/store or alias binding. Thus reads, stores, WITH and VAR-selected targets,
record/array pointer slots and chained dereferences share the same check.
Initialized NIL remains valid for copy, comparison, argument and result
transport. NEW never reads the previous destination pointer.

Failure flushes stdout, writes exactly one stderr line,
`runtime error: NILCK NIL pointer dereference at line L column C`, flushes
stderr and aborts. It does not return to later program operations. NILCK-
omits the guard; it does not make invalid accesses safe. Tests never execute
invalid unchecked twins.

## Explicit exclusions

This is **not** full historical NILCK. It does not validate arbitrary addresses,
allocation ownership, disposed aliases, address reuse or referent lifetime.
Valid ordinary pointers to foreign, stack and global storage are not rejected
merely because they did not originate in NEW. No pointer representation or
ABI changes, sentinel bit patterns, hidden-header reads or registry are used.

DISPOSE policy and instrumentation remain a separate open item. Host SUPER
ARRAY descriptors, UPPER, specialized INDEXCK/vector diagnostics and file `^`
buffers retain their existing independent behavior; they are not claimed as
NILCK consumers. This slice does not remove or recouple those checks.
CPU DEVICE and NVPTX ordinary pointer dereferences with NILCK+ reject with a
located `NILCK unsupported boundary: DEVICE pointer dereference` diagnostic
and publish no IR. NILCK- explicitly retains legacy DEVICE lowering. Existing
valid DEVICE ABI/arithmetic/launch tests opt out at their dereferences so they
continue testing those contracts without claiming pointer protection.

## Completion checklist

- [x] Ratify null-only ordinary host scope, selector-token snapshots and
  unchecked legacy/malformed metadata policy.
- [x] Centralize checks after INITCK/load and before address/access or aliases.
- [x] Located, flushed, nonreturning diagnostic distinct from INITCK/INDEXCK.
- [x] Null read/store/WITH/VAR, selected record/array slots, chained pointers
  and returned-pointer regressions, both dialects at O0–O3.
- [x] Valid on/off twins, copy/compare/formals/results, stack-pointer access,
  selected aliases and once-only index evaluation, both dialects at O0–O3.
- [x] INITCK-first execution and O0 metadata/load/null-check/shadow/store order.
- [x] Selector directive transitions, numeric NILCK, DEBUG and PUSH/POP,
  legacy/malformed snapshots and missing-location IR regressions.
- [x] CPU DEVICE/NVPTX enabled rejection/no-IR and disabled compilation.
- [x] Wire `tests/contract/nilck.sh` into the automatic contract tier.
- [x] Clean no-Python bootstrap, all four gen3/gen4 binary comparisons,
  bootstrap-subset checks and full routine regression suite (67/67 suites).
  Validation commands: `scripts/beautify.sh`, `make test-bootstrap`, `make test`.
- [ ] DISPOSE token/policy, descriptor ownership and full consumer/ABI audit.
- [ ] Lifetime/provenance design, if separately approved; null checks provide
  no disposed-pointer guarantee.

## Validation

Run `make test` for all routine tiers, including this suite, descriptors and
INITCK integration. `make all` rebuilds the four compiler generations and
compares gen3/gen4 binaries; `tests/check/bootstrap_subset.sh` enforces the
pasboot subset. Invalid unchecked pointers are compile-only. Optional GPU
hardware execution is not part of this first slice.
