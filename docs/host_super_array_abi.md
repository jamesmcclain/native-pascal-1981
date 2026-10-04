# Host SUPER ARRAY descriptor ABI

Status: **first-milestone descriptor transport and explicit unsafe boundaries
implemented**. Host storage, native calls/results, selected UPPER/vector bounds,
NIL/equality, layout and unsupported-boundary rejection use this ABI. Unsafe
imports validate supplied metadata/alignment/span before constructing a value.
Host SUPER ARRAY NEW now validates bounds/domain, widened count/byte size and
allocation success before publishing the complete descriptor. `$INDEXCK+`
checks scalar subscripts against the selected descriptor's declared lower and
actual upper, and fails deterministically on a NIL descriptor before any
data access. Matching DISPOSE
uses direct element allocations (no header).

**Still deferred:** borrowed non-pointer
formals and dangling-alias detection. Over-aligned NEW elements (>16-byte alignment) are
explicitly rejected. DEVICE lowering is unchanged, including thin pointers in
DEVICE interfaces spliced into a host module. Imported host descriptor
parameters/results/storage are rejected in DEVICE code rather than silently
reinterpreted as thin pointers; opaque raw-only interfaces remain usable.
Rebuild all affected host objects.

The original design/source audit below was against
`f86a649a65e91343b98a21dc0eefbce5cc2f92c5`; its source line ranges are historical
navigation evidence, not current line numbers. See
[dialect_notes.md](dialect_notes.md) for implemented behavior and remaining limits.

## Scope and ABI break

The first implementation milestone covers native host `^SUPER ARRAY` values:
assignment, aliases, record/array slots, value and reference pointer parameters,
function results and selected dereferences. Borrowed non-pointer SUPER ARRAY
formals are a second milestone. DEVICE storage and lowering are unchanged.
Unsupported bound-dependent forms must fail explicitly, never become thin
pointers or infer bounds from memory before an arbitrary address.

The supported host is the existing x86-64 Linux/SysV target and DataLayout in
`src/codegen.pas:284–300`. Other host targets require a new layout/ABI audit.
There is deliberately no old-object compatibility: rebuild affected host units,
callers and callees together. The break includes descriptor slots, enclosing
record layouts, array strides, SIZEOF, typed-file element layouts and native
parameter/result conventions. Descriptor-containing binary data is process-local
memory representation, not a portable serialization or a safe reconstruction
mechanism; reading arbitrary bytes into such slots is unsafe and supplies no
validity, ownership or lifetime guarantee.

## Storage, type identity and bound representation

A host super-array pointer has nonpacked LLVM storage `{ptr, i64}`:

| Field | Offset | Meaning |
| --- | --- | --- |
| data | 0 | Address of first element (declared lower index) |
| upper | 8 | Actual inclusive upper, signed INTEGER64 |

Size is 16 bytes and alignment is 8 on the supported target. The declared lower,
index domain and element identity belong to immutable type metadata, not the
value. Descriptor arrays have 16-byte stride; enclosing aggregates use their
normal natural padding. There is no bound header before data.

Canonical NIL is `{null, 0}`. Its upper is not an array bound. NIL tests and
pointer equality/inequality compare data addresses only, not upper fields;
ordering and pointer arithmetic on descriptors are rejected. Bounds do not
establish liveness and dangling aliases after DISPOSE remain outside the contract.

Same resolved pointer-type identity is required for assignment, arguments and
results, including aliases (`TYPE Q = P`). Separate pointer declarations are not
made compatible just because their storage layouts match. Type identity includes
the referent, lower/index domain and pointer flavor/space. VAR/reference actuals
must have the matching descriptor storage type. Ordinary thin-pointer rules are
not otherwise changed. NIL literals receive explicit whole-descriptor coercion;
an arbitrary ADRMEM value equal to zero is not a NIL literal conversion.

Retain the existing declared-lower grammar and supported ordinal
kinds; do not introduce INTEGER64/WORD64 declared-lower syntax in this migration.
Resolve lower, ordinal host identity and domain limits consistently in both
compiler phases. INTEGER, WORD, CHAR, BOOLEAN and enum/subrange domains retain
their declared domain limits. An unresolved or unsupported domain is rejected,
not defaulted to INTEGER. NEW and unsafe import require upper within that domain
and within signed INTEGER64, and upper >= lower. A wider bound expression is
checked before conversion; WORD64 above INT64_MAX cannot wrap into a bound.
The i64 carrier does not broaden source-language domains. LOWER and UPPER retain
INTEGER64 result types and their existing evaluation contract: LOWER is type-only;
UPPER evaluates the selected pointer once and diagnoses final NIL before using
upper. This chooses signed i64 rather than domain-tagged unsigned i64 bounds.

## Whole-value transport and native calls

Load, copy and store the complete descriptor in assignment, parameter temporaries,
record/array fields and result slots. Transactional publication means no
compiler-generated destination store before validation/allocation succeeds; it
is not an atomicity or concurrent-access guarantee.

Use the existing explicit SysV aggregate machinery rather than assuming that a
LLVM struct signature automatically gives the desired object ABI. A descriptor
has two INTEGER-class eightbytes: value arguments use two i64 coercion pieces;
results use the matching `{i64, i64}` coerced result. Storage remains `{ptr, i64}`.
Reference parameters (VAR and other supported reference modes) pass one address
of the complete descriptor slot, not its element-data pointer. Recursively visit
both leaves inside aggregates; existing aggregate register/MEMORY and byval/sret
rules apply, including available-register accounting. Declaration, call site,
callee reconstruction and return reconstruction must change together.

The shared designator path must carry selected descriptor metadata separately
from the element address. For `record.p^[i]` or `a[j]^[i]`, use that selected
pointer's descriptor, never a declaration-wide last allocation. UPPER, scalar
subscripts and VLOAD/VSTORE consume the same actual bound source. Preserve
VLOAD/VSTORE's existing transfer-check policy independently of scalar INDEXCK.

## Explicit unsafe C raw-pointer boundary

Reserve extended-dialect intrinsics (subject to normal builtin shadowing):

- `UNSAFERAW(p)` returns CPTR/ADRMEM, extracting data only. Evaluate p once;
  NIL exports null. This never returns descriptor-slot storage.
- `UNSAFESUPER(P, raw, lower, upper)` returns descriptor pointer type P. P is a
  type argument, as with RETYPE; it must resolve to a supported host super-array
  pointer. Raw must be CPTR/ADRMEM or a compatible thin host element pointer,
  not an integer, ADS pointer or another descriptor. Runtime arguments each
  execute once; their relative evaluation order is unspecified.

Import requires supplied lower to equal P's declared lower, representable/domain-
valid upper >= lower, nonnull data, correct element alignment, and count/stride/
byte-span/address arithmetic that fits the supported host address/size domain.
Use widened arithmetic before any narrowing. Checks always apply, including
under INDEXCK-. Failure is deterministic and non-returning, before publishing a
result; never dereference raw or inspect raw-8. Use NIL assignment instead of a
null import. Exact diagnostic messages will be pinned by implementation tests.

These checks establish metadata/arithmetic validity only. The caller warrants
contiguous storage of the stated extent, valid element representation, permitted
read/write access and sufficient lifetime. Alignment or a nonnull pointer proves
neither allocation origin nor accessible capacity. Raw pointers returned by C
require explicit import before any descriptor use, checked or unchecked.

Ownership is an unsafe precondition, not a descriptor bit or typestate promise:
import does not grant ownership. DISPOSE on an imported value or any alias is
valid only when the caller guarantees the exact native allocation/free contract
and exclusive right to free it. Borrowed C/stack storage fails that precondition.
There is no promised compile-time or runtime detection of this misuse. If such
detection is later required, revise ownership representation/types separately;
a two-word descriptor cannot enforce it through arbitrary aliases.

Both intrinsics issue a compile-time `unsafe-super-array-conversion` warning.
This identifier is stable; warning-as-error control syntax is deferred. In vintage
mode and DEVICE code these intrinsics are rejected. Reject implicit descriptor
conversion to/from ADRMEM, CPTR, thin pointers or ADS, including address arithmetic,
RETYPE and numeric pointer READ/WRITE. Users may explicitly export for raw-address
printing, but numeric input cannot recreate a descriptor.

Reject C arguments/results containing descriptors recursively,
including VAR descriptor slots and by-value/reference enclosing aggregates.
Reject statically visible opaque-pointer/address escapes to descriptor-containing
storage, including ADR of such a slot or aggregate. ADR of a non-pointer SUPER
ARRAY referent is unsupported until a borrowed-view/address contract is designed.
Do not mislabel ADR(slot) as element-data export. Arbitrary user raw-memory
operations remain unsafe; the compiler cannot prove what an opaque address hides.
Direct host descriptor LAUNCH arguments and ADS conversions are rejected.
DEVCOPY/DEVFREE require explicit raw export where applicable; copying descriptor
bytes does not convert them to DEVICE representations or transfer ownership.

## Allocation and checked-access dependencies

NEW evaluates destination selection and upper once, validates domain, count,
size and alignment arithmetic, allocates successfully, then publishes the full
descriptor. Checks apply even under INDEXCK-. `pas_super_new` performs arithmetic
in 128 bits, rejects WORD64 bounds above INT64_MAX, upper below lower, upper
outside the declared domain, count beyond SIZE_MAX and bytes beyond SIZE_MAX or
PTRDIFF_MAX, then rejects a NULL malloc result. Failures print
`runtime error: NEW SUPER ARRAY <reason>` and abort; exact reasons are covered
by `tests/super_new_contract.sh`. The helper has no destination address: only a
successful return can reach the compiler's single whole-descriptor store.
Destination selection and upper expression each run once; their own side effects
are not rolled back. There is no concurrent/atomic publication guarantee.

Element strides/alignment use LLVM's actual allocation layout, not narrow SIZEOF
arithmetic. Array element layouts beyond signed host size are rejected before
querying an overflowing LLVM layout. Record element layouts retain the compiler's
32-bit field-offset limit; unsupported oversized records are explicitly rejected.
Nested non-pointer SUPER ARRAY elements have no static extent and are rejected.
These layout checks also keep unsafe-import span validation consistent with NEW.
It does not add mandatory element zero-initialization. Use an
alignment-capable allocator whose result is directly compatible with the matching
free operation; do not adjust the data pointer without retaining a recoverable
free base. Over-aligned elements must either be supported by that allocation
contract or explicitly rejected. DISPOSE frees the correct allocation base;
aliases are not invalidated or made safe by this ABI.

Implemented: `$INDEXCK+` checks the scalar index in widened signed/unsigned
i128 arithmetic against the declared lower and the selected descriptor's
actual upper before any offset/GEP, through the same `pas_array_index_error`
diagnostic as fixed arrays (bounds printed as declared lower..actual upper).
An executed index expression runs once; a checked constant outside the bounds
fails when the access runs, not at compile time. `$INDEXCK-` suppresses the
scalar guard, not descriptor transport or import/NEW validation; a borrowed
non-pointer subscript is still rejected outright. DEVICE compilands keep no
guard.

Implemented alongside it: a checked subscript through a NIL descriptor fails
deterministically via `pas_super_index_nil_error` (`runtime error: index
through NIL super-array pointer`) **before** the bound comparison and before
any address formation, so no data access occurs. The NIL check precedes the
bounds check, so a NIL descriptor is diagnosed as NIL regardless of the
index; the index expression itself has already run exactly once, and its
ordering relative to the NIL failure is deliberately not pinned down.
`$INDEXCK-`/`$INDEXCK+` snapshot semantics (per-index snapshots, in-expression
directives affecting only subsequent indexes) are probed for super subscripts
in `tests/indexck_guard_ir.sh` alongside guard-free IR for disabled checks.

Still deferred: borrowed non-pointer formals and dangling-alias detection. The
guards never read a pre-data header and do not make a dangling descriptor safe.

## Audited integration map

Line ranges refer to the audited HEAD; they are navigation evidence, not a claim
that these are the only lines requiring edits.

| Source | Existing assumption / integration responsibility |
| --- | --- |
| `src/cg_types.pas:178–258,469–482` | Thin-pointer wildcard compatibility and unchanged-value coercion; add representation-aware identity and NIL conversion. |
| `src/cg_types.pas:665–870,1568–1592,1719–1766` | Eight-byte pointer layout/scalar ABI leaf; SUPER lacks fixed-array domain propagation; centralize descriptor predicate/layout/domain/leaf helpers. |
| `src/cg_decl.pas:730–763,1305–1444` | Value-copy/aggregate gates, routine signatures, reference and SysV lowering; mirror caller and body reconstruction. |
| `src/cg_expr.pas:330–354,451–509,634–981` | NIL promotion, pointer arithmetic/comparison, call marshalling/results. |
| `src/cg_expr.pas:1040–1379,1684–1707,1859–1956` | Shared designators, ADR storage escape, header-based UPPER and cast boundaries. |
| `src/cg_stmt.pas:225–286,1170–1184,1266–1307,1420–1528` | Whole stores, LAUNCH/raw device helpers, header-based NEW/DISPOSE and returns. |
| `src/cg_expr_vector.pas:451–534` | Header-based bound lookup and vector checks. |
| `src/tc_expr.pas:250–279,1096–1111`; `src/tc_types.pas:639–684` | Coarse pointer compatibility/NIL tags and ordinal metadata; typecheck rejection plus codegen backstop for frozen ASTs. |
| `src/cg_io.pas:221–229,534,933` | Numeric pointer output/input must not drop or fabricate descriptor bounds. |
| `src/cg_symbols.pas:76–114`; `src/cg_decl.pas:395–416` | Typed zero initializers and typed-file element sizes; audit descriptor-containing raw persistence. |

Validation must inspect host IR for 16-byte storage/stride, recursive aggregate
ABI pieces, matching declarations/calls/results, VAR slot addresses, canonical
NIL and absence of header loads. Exercise two allocation sizes, aliases, selected
fields/array elements, value/VAR/result flows and nonzero lower. Add negative
foreign/raw/DEVICE and numeric-I/O tests; preserve device IR and existing bounds/
vector behavior. Audit unit interfaces, external varargs and raw-memory routes
recursively; do not treat an opaque pointer's spelling as proof of safety.
Relevant entry points are `tests/indexck_guard_ir.sh`, `tests/indexck_metadata.sh`,
`tests/golden/bound_expression_*.pas`, `make test-native` and `make test-driver`.
The original specification-only commit did not run compiler tests. The
implementation is validated by `make test-descriptor-contract` (also part of
`make test-native`), native driver/golden/checklit/depth/stage/AST suites and the
INDEXCK metadata/guard probes. The descriptor suite includes separate native
unit caller/callee compilation, register-exhaustion/byval/sret probes, ordinal
domains, explicit import/export warnings and shadowing, mandatory import failures
under INDEXCK-, recursive C/address exclusions and DEVICE preservation. See
[the descriptor test coverage](../tests/descriptor/README.md).

## Evidence and limits

IBM Pascal Compiler, August 1981, printed pp. 6-43 (descriptor representation),
6-35 (address without bounds), 6-29–6-31 (pointer identity/operations), 6-15–6-16
(super bounds/NEW), and 10-16–10-17 (historical return convention). Local OCR
`IBM_Pascal_Compiler_Aug81_djvu.txt` lines 7943–7963, 7593–7604, 7325–7396,
6636–6701 and 11000–11058 respectively; OCR was not verified against scan images.
[Manual scan](https://www.bitsavers.org/pdf/ibm/pc/languages/IBM_Pascal_Compiler_Aug81.pdf).
Historical address widths, 16-bit bound encoding and return registers are not
adopted as the native ABI.

[LLVM LangRef](https://llvm.org/docs/LangRef.html) supports aggregate load/store,
call/return and DataLayout-based padding; it does not guarantee atomic aggregate
publication or C ABI compatibility merely from struct spelling. Native signed
INTEGER64 bounds, equality-by-data, unsafe syntax/ownership policy and deterministic
validation failures above are explicit local decisions, not historical parity
claims. Borrowed formals, DEVICE descriptors and temporal safety remain deferred.
