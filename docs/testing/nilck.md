# NILCK: null-only host pointer dereferences and DISPOSE

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

### DISPOSE policy and source site

The IBM Pascal Compiler manual (August 1981), p. 11-5, says a DISPOSE pointer
must not be NIL, uninitialized or already disposed, adding **“these are checked
if $NILCK is on.”** The NILCK description on p. 4-25 also includes pointers
“passed to DISPOSE.” The appendix's terse “DISPOSE or $NILCK+” error descriptions
are not treated as overriding that explicit qualification. The OCR evidence is
at `~/PASCAL/IBM_Pascal_Compiler_Aug81_djvu.txt:11824–11829` and `:4788–4812`;
this is a documented interpretation, not comparison with an original compiler.

Accordingly, builtin DISPOSE's **name token** supplies `meta_flags.NILCK` and
`location`; directives within its actual do not retroactively change disposal
policy. A selected actual's own `^` or index has its independent snapshot.
Typechecking preserves the existing statement metadata; legacy/malformed
boolean enablement opts out and missing location reports 0:0.

For ordinary pointers and host SUPER-array descriptors, DISPOSE evaluates the
slot once, performs any supported INITCK check, loads the pointer/descriptor
once, extracts descriptor data if needed, and checks that data pointer for NIL
before retiring INITCK registration or calling free. The failure branch changes
neither pointer bits nor descriptor/registration. Successful disposal retains
the existing behavior: it does not clear the pointer or its initialization
state. A disposed pointer is not made safe by remaining initialized.

NILCK+ failure is one flushed, nonreturning diagnostic:
`runtime error: NILCK NIL pointer passed to DISPOSE at line L column C`.
NILCK- omits this check; host `free(NULL)` currently succeeds, but unchecked
invalid/disposed pointers remain unsafe. No mandatory null validation is added
under NILCK-. User routines shadowing DISPOSE are unaffected. DEVICE NEW/DISPOSE
remain rejected regardless of NILCK, by their existing allocation boundary.

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

Host SUPER ARRAY descriptor **dereferences**, UPPER, specialized INDEXCK/vector
diagnostics and file `^` buffers retain their existing independent behavior;
they are not claimed as NILCK consumers. Descriptor **DISPOSE data pointers**
are null-checked as described above. This slice does not remove or recouple
existing descriptor checks. Historical long-form DISPOSE size checks are not
implemented here; the existing one-argument admission rule is unchanged.
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
- [x] NILCK-controlled DISPOSE name-token policy, ordinary and descriptor data
  null guards before retirement/free, located nonreturning diagnostic.
- [x] `tests/contract/nilck_dispose.sh`: default-on null cases and valid on/off
  twins in both dialects at O0–O3; selected field/array slots, pointer chains,
  VAR/formal/result/copy paths, once-only index evaluation, initialized NIL and
  uninitialized ordinary/descriptor locals with INITCK+, token/actual directive
  independence, legacy/malformed metadata, missing location and shadowing.
- [x] O0 INITCK/load/null-check/retirement/free ordering and write-free failure
  blocks; runtime retirement/free interposition and removed-guard negative
  control demonstrate failure before side effects.
- [x] DISPOSE follow-up validation: formatting, clean no-Python
  `make test-bootstrap`, all four gen3/gen4 fixed-point comparisons and
  full `make test` (**68/68 suites passed**).
- [ ] Descriptor dereference ownership and full consumer/ABI audit.
- [ ] Lifetime/provenance design, if separately approved; null checks provide
  no disposed-pointer guarantee.

## Validation

Run `make test` for all routine tiers, including both NILCK suites, descriptors and
INITCK integration. `make all` rebuilds the four compiler generations and
compares gen3/gen4 binaries; `tests/check/bootstrap_subset.sh` enforces the
pasboot subset. Invalid unchecked pointers are compile-only. Optional GPU
hardware execution is not part of this first slice.
