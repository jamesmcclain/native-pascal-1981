# COPYLST admission and RANGECK capacity checks

Validation on `port`: 123 focused COPYLST checks and 95 existing CONCAT checks
passed. Clean `make -j8 test-bootstrap` passed without Python, with identical
gen3/gen4 stage binaries. Full `make test TEST_JOBS=8 BUILD_JOBS=8` passed
69/69 suites. The baseline regression failed on missing COPYLST admission.

Run `tests/contract/rangeck_copylst.sh` after `make`, or select
`make test SUITES=rangeck_copylst`.

The suite covers the bounded COPYLST contract in
[dialect notes](../dialect_notes.md#copylst-admission-and-capacity-checks-native):

- Both dialects, RANGECK on/off and O0–O3 for valid empty, exact-capacity,
  literal, fixed-source, self-copy, selected-source, CONST/VAR-formal and
  once-only function-source calls. Length 255 is valid even with capacity 256.
- Enabled overflow failures at O0–O3 for capacity 0/3/255/256 and bare LSTRING;
  fixed source length 256 cannot wrap into an accepted byte length. Exact
  diagnostics, source coordinates, flushed prefix and exit 134 are checked.
- Wrong arity/types, fixed STRING/constant/function/missing destinations and
  selected destinations are rejected by the typechecker. User-declared
  COPYLST remains an ordinary call.
- A dynamic function result supplies an oversized source. O0 IR asserts a
  full-width guard and terminating failure edge before copy/length publication.
  Test-only C abort wrapping at O0–O3 compares all destination and neighbor
  bytes against snapshots and verifies the source ran exactly once. The C
  observer requires the extended dialect; production code has no test hooks.
- A scratch-IR mutation bypasses the branch and must fail the ordering checker.
  The unsafe mutated IR is never executed.
- RANGECK is independent of MATHCK. First-token, nested/sibling and legacy
  AST policy/location are checked. INITCK-enabled mutable string/function
  sources remain explicit boundaries; literal sources need no shadow and
  naming a write-only destination does not read it.
- CPU DEVICE guards and traps; NVPTX retains the unchecked boundary, with no
  host-runtime diagnostic call. Invalid RANGECK-off copies are IR-only tests.

This does not complete R5: general whole-string assignment/value parameters,
other mutators, arbitrary aliases and I/O/foreign/raw-memory producers remain
separate work. It does not add source provenance/liveness checks or general
STRING/LSTRING subscript bounds. A malformed source length can still violate
its own storage extent even if the destination is large enough; destination
capacity checking is not an unconditional memory-safety guarantee.
