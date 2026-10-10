# Dialect notes: dialects, widths, and the things that fail silently

This is the document to read before writing Pascal in this repository. It
records the parts of the 1981 IBM Pascal dialect that do not behave the way a
modern Pascal or C programmer expects, with a bias toward the ones that fail
*silently* — no error, no warning, just a wrong number somewhere downstream.

Everything here has been verified against the native compiler in this tree
rather than inferred from its sources.

> **Writing GPU kernels?** NVPTX DEVICE code must turn `$MATHCK` off
> (`{$MATHCK-}`) for any integer `+ - * DIV MOD`, unary `-`, `SUCC`, `PRED`,
> `ABS` or `SQR`, or it does not compile: the GPU cannot report MATHCK's
> run-time errors, and the compiler will not silently drop a check you asked
> for. Arithmetic in those kernels is then unchecked and wraps. See
> [GPU (NVPTX) kernels need `{$MATHCK-}`](#gpu-nvptx-kernels-need-mathck--for-integer-arithmetic-extended).

Compiler and runtime scratch storage, including anonymous Pascal FILE storage
and `SysTempDirCreate`, is covered by the canonical
[temporary-file ownership contract](temporary_files.md). Harness and editor
cleanup rules live there too; they are not dialect differences.

Host pointer interoperability is defined by the
[SUPER ARRAY descriptor ABI](#host-super-array-descriptor-abi-native), including
its [unsafe raw boundary](#descriptor-unsafe-raw-boundary) and ownership limits.

## Contents

- [There are two command-line dialects](#there-are-two-command-line-dialects)
- [Initialization checking: host storage](#initialization-checking-host-storage-native)
- [Enumerated and BOOLEAN I/O](#enumerated-and-boolean-io)
- [Wide signed integer input](#wide-signed-integer-input-extended)
- [String precision](#string-precision)
- [READSET and tuning hints](#readset-and-tuning-hints)
- [GPU (NVPTX) kernels need `{$MATHCK-}` for integer arithmetic](#gpu-nvptx-kernels-need-mathck--for-integer-arithmetic-extended)
- [Vectors (SIMD)](#vectors-simd-extended)
- [BOOLEAN set constructors](#boolean-set-constructors-native)
- [Set base compatibility](#set-base-compatibility-native)
- [Set constructor element range](#set-constructor-element-range-native)
- [BOOLEAN membership](#boolean-membership-native)
- [AND THEN and OR ELSE](#and-then-and-or-else-both)
- [Host SUPER ARRAY descriptor ABI](#host-super-array-descriptor-abi-native)
- [Bound expressions](#bound-expressions-native)
- [Subrange range checks](#subrange-range-checks-native)
- [Named ordinal array index types](#named-ordinal-array-index-types-native)
- [MATHCK: integer overflow and division checks](#mathck-integer-overflow-and-division-checks-both)
- [Integer widths](#integer-widths)
- [Integer constants and context](#integer-constants-and-context)
- [`TRUNC` and `ROUND` return `INTEGER`, so they narrow to 16 bits](#trunc-and-round-return-integer-so-they-narrow-to-16-bits-both)
- [Differences from the Python compiler](#differences-from-the-python-compiler)
- [Native limitations](#native-limitations-native)
- [Other things that cost time](#other-things-that-cost-time-both-unless-marked-otherwise)
- [Checklist before committing Pascal in this tree](#checklist-before-committing-pascal-in-this-tree)

## There are two command-line dialects

The native compiler has a **vintage** dialect and an **extended** dialect.
The default is `vintage`. This dialect implements the 1981 language, including
16-bit `INTEGER` and `WORD` types. Enum I/O uses ordinals, and string precision
has no effect.

The `extended` dialect activates these feature groups:

- `wide-integers`: `INTEGER8`, `INTEGER32`, `INTEGER64`, `WORD8`, `WORD32`,
  `WORD64`, the `INTEGER16` and `WORD16` synonyms, and wide integer constants.
- `wide-reals`: `REAL32`, and `REAL64` as a synonym for `REAL`.
- `symbolic-enum-io`, `string-precision`, `readset-set-literal`, and
  `tuning-hints`.
- C interoperability types and attributes.

Vintage mode rejects wide scalar type names, `WRD8`, C ABI type aliases, and
`[C]`, `[CDECL]`, and `[VARARGS]`. It also rejects anonymous `READSET` set
literals and `{$UNROLL}` outside DEVICE code.

### Command-line contract

The driver accepts only `vintage` and `extended` as case-sensitive dialect
values. The driver uses `vintage` when the command does not contain a dialect
option. For example:

```sh
mkdir -p -m 700 /tmp/native-pascal-1981
work=$(mktemp -d /tmp/native-pascal-1981/example.XXXXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
bin/pascal1981 -S tests/corpus/golden/01_hello.pas -o "$work/hello.ll"
bin/pascal1981 --dialect extended -S tests/corpus/golden/01_hello.pas -o "$work/hello.ll"
```

The standalone parser, typechecker, and code generator also default to
`vintage`. These stages accept data only on standard input. An explicit
extended pipeline has this form (using the workspace above):

```sh
bin/lexer < tests/corpus/golden/01_hello.pas |
  bin/parser --dialect extended |
  bin/typechecker --dialect extended |
  bin/codegen --dialect extended > "$work/hello.ll"
```

The lexer is dialect-neutral. It creates the same token stream for both
dialects and records directive metadata for later stages. Do not pass a
dialect option to the lexer.

The driver reports `error: --dialect requires an argument` when the value is
missing. It reports `error: invalid dialect '<value>'; expected 'vintage' or
'extended'` when the value is invalid. The standalone stages report equivalent
errors.

The typechecker and code generator resolve the dialect to a shared feature
set. They use this set for scalar types, integer ranges, C interoperability,
`READSET`, tuning hints, enum I/O, and string precision.

`DEVICE` is a compiland kind, not a command-line dialect. DEVICE context can
activate wide scalar types and tuning hints independently of `--dialect`.
The command line does not accept `device` as a dialect value.

The native command line does not support `-f` feature overrides. Thus, users
cannot activate one extended feature in vintage mode. Use `--dialect extended`
to activate the complete extended feature set.

### Host clang invocation

The driver hands the generated IR to `clang` (or `$PASCAL1981_CC`, then
`$CC`) to compile and link, with no target option, so clang uses its own
default triple, runtime library layout and linker. Host IR states
`x86_64-pc-linux-gnu`; a clang whose default triple differs only in vendor
(`x86_64-unknown-linux-gnu`, typical of source builds) warns
`-Woverride-module` and compiles it for its own triple, which is the same
target. Do not pass `--target` from the driver to silence that: a clang
that installs its runtime libraries under its default triple
(`lib/clang/N/lib/x86_64-unknown-linux-gnu/`) then fails to find
`libclang_rt.builtins.a` when linking.

Clang warnings, including ones about the host's toolchain installation
such as LLVM 22's `-Wgcc-install-dir-libstdcxx`, reach the driver's stderr
unchanged. Test suites do not depend on them: see
[Host compiler warnings](../tests/README.md#host-compiler-warnings).

### Bootstrap dialect

Compiler sources use extended types and C interoperability declarations.
Generation 1 is built by `bootstrap/pasboot`, which accepts only the
[bootstrap subset](bootstrap_subset.md) of the extended dialect.
`scripts/build-stage.sh` passes `--dialect extended` to each parser,
typechecker, and code generator that builds these sources. It does not pass a
dialect option to a lexer. Use `make test-bootstrap` to rebuild all bootstrap
generations and check the `gen3` and `gen4` fixed point.

The scope tags below state where a rule applies: **[both]** means a
vintage-core rule that remains true in the native extended surface;
**[extended]** means the rule concerns an extension; and **[native]** means a
limitation of this repository's implementation. A native limitation applies
to every program compiled by the native pipeline unless the text says
otherwise.

## Initialization checking: host storage [native]

INITCK is runtime enforcement, not metadata-only. It is default-off and
read-site controlled; supported writes and unchecked transfers maintain shadow
state regardless of that flag. The implemented slices and regression anchors
are summarized below; the detailed rules and unsupported-boundary table in
this section define the limits, not the presence of a directive.

| Implemented slice / boundary | Focused tests in `tests/` |
|---|---|
| INTEGER/BOOLEAN/CHAR locals, read-site flags and fresh activation state | `initck_contract.sh`, `initck_state.sh`, `initck_scalar.sh` |
| Proven scalar-local guard elimination (conservative must-analysis) | `initck_definite.sh` |
| Unchecked scalar copies, READ/READLN and FOR producers | `initck_producers.sh` |
| Value/VAR/CONST scalar formals, scalar results and WITH aliases | `initck_routines.sh` |
| Fixed ARRAY/RECORD logical leaves, strict checked copies, unchecked state propagation and variant views | `initck_aggregates.sh` |
| Typed pointer/descriptor leaves, NEW referents and SUPER elements, publication and retirement | `initck_heap.sh` |
| C/raw escape contracts, tracked file buffers and host-only DEVICE diagnostics | `initck_external.sh` |
| Initialized on/off output, guarded vs unguarded IR, partial aliases/calls | `initck_validation.sh` |
| Unchanged Pascal ABI and descriptor layout (not aggregate-result enforcement) | `initck_abi.sh`, `descriptor_contract.sh` |

Enabled and disabled INITCK IR are **not** expected to be identical for
supported checked reads.
At O0 the release matrix requires located guards for scalar/pointer reads,
aggregate copies/elements, heap leaves, formals and results; disabled twins
have no INITCK failure calls but still carry shadow state and copy/heap
bookkeeping. Initialized output must agree in both dialects at O0/O1/O2/O3.
Disabled uninitialized-read probes are compile-only. Identical IR remains an
oracle only for legacy/missing-read-snapshot opt-outs, not enabled enforcement.

`{$INITCK+}` guards actually evaluated direct reads of ordinary host automatic
locals of exact INTEGER, BOOLEAN, or CHAR type in their declaring routine.
Each activation has a separate `i1` shadow slot, reset to false without touching
the Pascal value bytes. A direct assignment marks it true **after** evaluation,
coercion and the successful data store, even under INITCK-. An enabled read
branches on shadow state before loading the value unless compile-time
must-analysis has proved that particular read initialized. Failure flushes stdout,
prints `runtime error: INITCK uninitialized local <name> at line <line> column
<column>` and aborts. The coordinates identify the consuming identifier token,
including inside parentheses, not the declaration or enclosing statement.
Expression factors carry optional `read_location` metadata through typechecking.
Checked older ASTs without positive line/column coordinates retain the name-only
diagnostic; missing coordinates never suppress an enabled guard. Tokens do not
currently carry filenames: include coordinates are local to the included token
run, so this diagnostic does not claim a source-file identity or include stack.
INITCK errors are distinct from existing NIL-pointer and array-bounds runtime
errors; this does not implement the NILCK directive. Zero, FALSE, and `-32768`
are ordinary initialized values, not sentinels.

Guard elimination runs even at O0, after unsupported-boundary validation. It
covers only exact INTEGER/BOOLEAN/CHAR non-parameter, non-WITH local slots that
retain shadow state. Facts start false per routine, follow direct assignments
of provably initialized scalar expressions (including checked reads that must
succeed before execution continues), and intersect at IF joins. An unchecked
unknown source kills the fact; known unchecked writes still establish it.
Calls, selected destinations, loops, WITH, returns and unfamiliar statements
are barriers, and expressions with calls/unknown forms are not annotated.
GOTO or labels disable the analysis for the entire routine. No aggregate,
heap, formal or result guard is optimized by this analysis. Proofs are internal
node identities, not trusted JSON annotations; table exhaustion keeps guards.
All data stores, shadow slots, unchecked propagation, runtime failures and
unsupported diagnostics retain their existing contract. This deliberately
bounded pass is not a general static rejection or interprocedural analysis.

Scalar producers of a tracked slot are: a direct assignment, a READ/READLN
destination, and a FOR control variable. An assignment or FOR initial value
whose evaluation performed an **unchecked** (INITCK-) read of tracked storage
carries that storage's state instead of marking the destination initialized:
`{$INITCK-} y := x + 1` leaves `y` unset when `x` was unset, so a later checked
read of `y` fails. Only evaluated operands contribute; a call to a Pascal
function with a tracked result contributes the state its return published (see
routine boundaries below). Any other untracked source (global, REAL, `[C]`
call result, ...) is outside coverage and contributes initialized. Implicit control flow is not tracked: a branch on an unchecked
unset value does not taint what the branch assigns. A READ/READLN destination
becomes initialized only after its conversion returns success; a trapped file
error keeps the prior state (stdin errors abort). A FOR control variable takes
the initial value's state when it is assigned and keeps it through the
iterations. After **natural** termination it is unset (the manual leaves its
value undefined, 9-17); BREAK and GOTO exits keep the value of the iteration
they left. The FOR statement's own bound comparisons are never INITCK consumers,
so FOR over excluded storage is not a boundary. `ADR` of the slot releases it
(external boundaries below), so natural FOR termination leaves an
address-taken control variable as it was. Builtins writing through an
address still disqualify the slot, and `VALUE` initialization is not
implemented.

Routine boundaries. A value formal of exact INTEGER, BOOLEAN or CHAR type is a
tracked slot of its activation that starts with the state of its evaluated
actual. The caller's read of the actual is an ordinary read: checked when
enabled there, and otherwise collected like an assignment RHS. An unset actual
under INITCK- therefore reaches the callee unset, and only a later checked read
fails (`uninitialized parameter <name>`). Passing an unset value that the
callee ignores or overwrites is never an error. A FUNCTION with such a result
type has a result state that starts unset in every activation. The retained
zero/default result bytes are not an initialization. Assignment to the function
name is a producer like any tracked assignment. Every normal return reads the
result it publishes: an explicit RETURN at the RETURN token, and the
fallthrough at the body's closing END. When INITCK is enabled at that token, an
unset result fails (`uninitialized result of <name>`). When it is disabled, the
default bytes are returned as before and the state travels to the caller's
value collection. Signatures never change. State crosses Pascal-to-Pascal host
calls through a thread-local runtime side channel (`pas_initck_args`,
`pas_initck_ret` in `runtime/initck.c`). The caller publishes pointers to its
actuals' states after evaluating every actual, and the callee copies and clears
them before making any call. An uninstrumented caller (for example C calling a
Pascal routine) publishes nothing, which reads as initialized. `[C]` routines
and DEVICE code take no part. Their formals are untracked, and a `[C]`
function's result is an untracked value. Each actual is evaluated in its own
state accumulator, so an unchecked unset read inside it reaches only a tracked
formal; the caller's value takes its state from the result (initialized for a
`[C]` function or a formal of an untracked type). A VAR or CONST formal of a tracked
type shares its caller's storage state: binding is not a read, a write through
the formal initializes the caller's storage (collecting the RHS state), and a
read checks it when enabled (`uninitialized parameter <name>`). Forwarding a
VAR formal keeps the original binding. An actual outside the slice (a global,
a component of untracked storage, an untracked type, or a C caller) binds a
private slot that is always initialized, so a checked read through such a binding cannot fail. That
is a coverage gap, not a guarantee. A VAR/CONST formal that escapes in the
callee (a VAR actual of an untracked formal type, a builtin, a nested declaration) releases its
caller's slot as initialized on entry, because untracked writes may follow. A
false positive in a correct caller is avoided at the cost of possibly missing
an unset value. VAR/CONST actuals of `[C]` routines and C-implemented plain
EXTERNs are covered under external boundaries below.
Tracked fixed-aggregate formals are covered by the aggregate rules below.
REAL and other untracked formals, and aggregate or otherwise untracked results,
stay excluded; an enabled RETURN/END of such a function is the `function result`
boundary.

Nested routines and WITH. A nested routine that redeclares a name (as a formal
or local, at any depth) owns separate storage, so the enclosing routine's local
of that name stays tracked. There is no static link, so a nested routine can
reach an enclosing local only by capturing it. That is unsupported by this
compiler (see the known deviations below): an enabled read of a captured local
is the `global or captured storage` boundary, and any mention disqualifies the
local. Inside a WITH body, a name that is not a field of any target is still the
routine's own tracked local. This holds only when every target's record type is
evident before lowering: its root is a variable or formal not nested in another
WITH, and its INDEX/FIELD/DEREF selectors resolve statically. A same-name field
shadows the local without touching it. Under a target whose type is not
evident (any WITH nested in another), mentioning the name conservatively
disqualifies the local. Fields bound from tracked record storage are tracked
(see aggregates below); fields of an untracked record are unsupported
storage, also when a builtin or output consumes them.

Aggregates. A host automatic local whose type is a fixed (non-SUPER) ARRAY or
a RECORD built, at any depth, only from INTEGER, BOOLEAN and CHAR leaves gets
one shadow state per scalar leaf, laid out like the data (an array of element
shadows; a record's fields in declaration order). It starts with every leaf
unset in each activation. A component selected by INDEX/FIELD down to a leaf
is tracked storage of its own: an assignment or READ/READLN to it initializes
that leaf only, never a neighboring element or sibling field, and an enabled
read checks that leaf (`uninitialized component <designator>`, e.g. `a[i]`,
`r.y`, `m[2].v[...]`; an index is spelled when it is a literal or a name).
Index operands are evaluated exactly once and bounds-checked first: the
element shadow reuses the data GEP's checked offset, so an out-of-range index
reports the bounds error, never INITCK. An unchecked component read is
collected like any tracked read. Selection operands are independent reads, so
mentioning a scalar in an index never disqualifies it. One untracked leaf (a
REAL, an ADS pointer, a string ...) leaves the whole object untracked.
Aggregate copies follow the strict checked-copy rule. An assignment whose
target or source names tracked aggregate storage whole (or a selected
sub-aggregate), and a value actual for an aggregate formal, are modeled
copies. When the source read is enabled, every transferred leaf must be
initialized before the native load (`uninitialized part of <designator>`),
even for a self-copy or an argument the callee ignores. After the data store
the destination takes the source's leaf states exactly (`pas_initck_copy`),
so an unchecked partial source never yields a wholly initialized destination.
Unset state consumed while selecting the source (an unchecked index with unset
state) leaves the destination wholly unset. An untracked source (a global, a
function result, a literal) counts as initialized, as for scalars. A tracked
aggregate value formal of a Pascal routine starts with a snapshot of its
actual's leaves, published through the same side channel as scalar actuals
(`pas_initck_receive`; nothing published means initialized). A VAR or CONST formal of a Pascal routine whose type is tracked (a scalar or
an aggregate) shares the actual's own state when the actual is tracked
storage: a direct slot, a selected leaf (`swap(a[1], a[2])`), a whole
aggregate or a sub-aggregate (`clear(m[2])`). The callee's writes initialize
exactly the leaves they write in the caller's storage and its enabled reads
check them; an escaping formal releases the bound leaves as initialized, as
for scalars. A WITH over tracked record storage (a tracked local or formal,
or a selected sub-record of one) binds each field to that field's own
leaves: reads are checked (`uninitialized field <name>`) and writes
initialize exactly that field. Every use of such a field in the body must
itself be modeled, else the whole object is disqualified. State therefore
follows storage through these aliases rather than names. Other whole uses,
binding to a builtin, and the `ADR` of a WITH-bound field still disqualify
the object; a `[C]` VAR/CONST binding and `ADR` of the whole variable
initialize it (external boundaries below).

Variant records use a logical-field model. Every field of every alternative
has its own leaf state even though alternatives share storage: a write
through one alternative neither initializes nor invalidates another, so
reading an overlapping field never written as such fails under INITCK+
(variant type punning needs INITCK- at that read, and the unchecked value then
carries the unset state onward). The tag is an ordinary fixed field: changing
it neither initializes nor invalidates any alternative. A checked whole-value
transfer of a record with a variant part needs every fixed field (the tag
included) and at least one complete alternative, any one, not necessarily the
one the tag selects; an alternative with no fields is always complete.
Inactive alternatives present in the allocation are not consumed. This is not
tag or active-variant checking, and IBM's historical exclusion of variant
fields from INITCK is not reproduced. Unchecked transfers copy every
alternative's states as they are.

Representations. Variant alternatives are the only storage overlap inside
tracked objects. PACKED arrays and records are rejected by the native code
generator outright, so no bit-packed leaf exists; tracked BOOLEANs occupy a
byte each. Strings (including LSTRING `.LEN`, which is element 0 of the same
storage), sets and vectors (including BOOLEAN vectors) are never tracked, nor
is any aggregate containing one: an enabled read of their components is the
`untracked type` boundary.

Pointers and heap storage. The value of a plain host typed pointer (`^T`,
whatever T is; not an ADS pointer) is one tracked leaf, and so are a raw
address (ADRMEM, ADSMEM, CPTR) and a host SUPER ARRAY descriptor (its data address and upper bound together), so
pointer locals, formals, results, and pointer fields and elements of tracked
aggregates are tracked like INTEGER/BOOLEAN/CHAR storage. `NEW(p)` initializes
the destination pointer only, after the pointer is stored; naming it is not a
read of its old value. A dereference reads its pointer at the `^`: with INITCK
enabled at that `^`, an unset pointer fails before the native pointer load
(`uninitialized local p at line L column C` for `p^.v`, `uninitialized
component h.next` for `h.next^`), even when the designator is an assignment
target. `UPPER(p^)` and `UNSAFERAW(p)` read a descriptor the same way (before
UPPER's NIL check), and `DISPOSE(p)` reads `p` too, leaving the pointer's own
state unchanged: its stale value is a pointer-validity matter for NILCK, not
an initialization one. Comparisons, copies, value actuals and results follow
the scalar rules. A descriptor's state says only that the descriptor value was
written (by `NEW(p, n)`, `UNSAFESUPER`, a copy or NIL); the state of the
elements it locates is separate (below).

The referent of an ordinary `NEW` whose type is tracked (built only from the
leaves above, through fixed ARRAYs and RECORDs) has per-leaf state too. It
belongs to the allocation, not to a name: `NEW` records it with every leaf
unset after the allocation succeeds and before the pointer is published, and a
dereference finds it by the referent's address (`runtime/initck_heap.c`), so
every pointer to the referent sees the same state. Components reached through
`^` are then ordinary tracked storage: assignments, READ/READLN, WITH-bound
fields, VAR/CONST bindings and aggregate copies initialize exactly the leaves
they write, and enabled reads check them (`uninitialized component p^.w`,
`uninitialized part of p^`, `uninitialized field w` inside `WITH p^`). A
second `NEW(p)` gives a fresh, wholly unset referent. `NEW(p, n)` of a SUPER
ARRAY whose element type is tracked likewise leaves every leaf of every
element unset, recorded after `pas_super_new` succeeds and before the
descriptor is published (IBM INITCK excluded these components instead). Each
subscript `p^[i]` finds its element's state from the descriptor's data address
and bounds after the index and bounds checks; a part outside the registered
allocation (an INDEXCK- subscript out of range, or a descriptor whose bounds
do not match the allocation) is untracked, so the instrumentation never reads
or writes state beyond the allocation. If the state cannot be allocated,
`runtime error: INITCK heap state allocation failed` aborts before
publication, so a failed NEW publishes no pointer, no pointer state and no
referent state.

`DISPOSE` retires the referent's state before freeing it, so a later
allocation that reuses the address (a NEW starts afresh; memory from C is
untracked) never inherits it. This is not a use-after-free detector: a
dangling pointer reads as untracked storage, or sees the state of a later NEW
that reused its address, and a WITH or VAR alias kept across the DISPOSE is as
dangling as the data.

Heap state is per allocation, so a referent cannot be disqualified per routine
like a local. Instead, when its address reaches an effect whose writes are not
modeled (a WITH-bound field used as an ADR operand or other unmodeled alias, a
conversion of the pointer to ADRMEM or to a pointer to another type, a pointer
value handed to a `[C]` routine or a varargs call, a VAR/CONST actual of a
`[C]` routine or of an untracked formal type, a non-scalar builtin such as
`VSTORE(p^, ...)`, `UNSAFERAW`) the referent is **released**: from then on it
reads as untracked, initialized storage, which can miss an unset value but
cannot fail because of writes made through that escape. Each lookup of an
untracked or released referent gets that lookup site's own run of initialized
leaves (in the caller's frame), so aliases bound at different sites, such as
two VAR actuals of distinct untracked referents, never share state: an
unchecked write through one cannot fail a checked read through the other. Such a designator, and
a WITH whose body uses a field that way (the WITH then binds untracked
fields), is itself an unsupported enabled read. Memory that `NEW` did not
allocate (from C, or an `UNSAFESUPER` import) and a pointer reinterpreted as
another type are untracked and read as initialized. A plain (non-`[C]`) EXTERN that
turns out to be C releases the referent of each typed pointer it received
(external boundaries below). A referent whose
type is outside the slice (a REAL field, an enumeration, a string, ...) is
untracked storage: an enabled read of it is the `heap storage` boundary, as is
an enabled dereference of a pointer stored there. Every dereference of a
tracked referent looks its state up, also with INITCK off, so NEW-heavy
programs pay a runtime call per heap access.

External boundaries: C calls. Nothing outside the compiled Pascal tells
INITCK what it reads or writes, and an opaque call never marks storage
initialized beyond what it was handed. A `[C]` routine takes no part in the
state side channel. Its value actuals are ordinary caller reads (checked when
enabled), its result is an untracked value, and a VAR or CONST actual
initializes **exactly** the storage it binds (a scalar, a selected component,
a whole or sub-aggregate) at the call, after every actual is evaluated,
because C may write any of it: binding is not a read, neighboring components
and other variables keep their state, and a later actual reading the same
storage is checked against its old state (`cpair(x, x)` with `x` unset
fails). A pointer value actual's referent is likewise released at the call. CONST is treated like VAR here, since nothing makes C honor it. A
heap referent bound that way, or whose pointer C receives, is released
(above). A plain (non-`[C]`) EXTERN may be instrumented Pascal (another
compiland, a MODULE) or C, so calls that publish state carry a handshake: the
caller tags the call with the callee's address (`pas_initck_callee`), and a
plain EXTERN call also passes a flag (`pas_initck_ack`) that an instrumented
callee sets when the tag names it. After an unacknowledged call the storage
bound to its VAR/CONST formals and the referents of the typed pointers it
received are released, and its result is initialized. An acknowledged call is
tracked like any Pascal call. A Pascal routine that C calls back while C is
running such a call sees another routine's tag and treats its formals as
initialized, as for any uninstrumented caller, rather than binding the outer
call's slots. C retaining an address and writing through it after the call
is not modeled: the released state is already initialized, so this can only
miss, except when a later unchecked copy of unset data makes that storage
unset again before C's write (the same residual as heap release). Nested
storage C reaches only through the referent it received (`p^.next^`) is not
released.

External boundaries: raw addresses and unsafe conversions. A raw address
value (ADRMEM, ADSMEM, CPTR) is a tracked leaf like a typed pointer's value:
assignment, a `[C]` result (initialized), `ADR` and conversions produce it,
and reads, comparisons and value actuals check or transport it. INITCK never
follows a raw address to the storage it locates. `ADR x` of a local or formal
(the grammar takes only a bare name) releases every leaf of `x`, or of the
caller storage a VAR/CONST formal is bound to, **where the `ADR` is
evaluated**, or, inside a call's actuals, just before that call, after every
actual is evaluated (`cadr(ADR x, x)` still checks `x`), however many such
effects one call's actuals hold; `x` stays tracked. A deferred release of an
`ADR` on an `AND THEN`/`OR ELSE` operand happens only if that operand was
evaluated. (Only a condition's top operator can be `AND THEN`/`OR ELSE` in
source, so this matters only for typed ASTs given to the code generator.) A
read before that point, an `ADR` on an untaken path and other variables are still checked, and writes through the
address (`fillc(ADR flags, ...)`, `q := ADR x; q^ := 99`, C) need no state
because the released leaves are already initialized. A typed pointer
converted from such an address locates no registered allocation, so reads
through it are untracked. An address-taken control variable is not unset by
natural FOR termination. The same residual as for releases above remains: an
unchecked copy of unset data into the variable after its `ADR` can make it
unset again before a raw write (as can a FOR over a VAR formal bound to
address-taken caller storage). The `ADR` of a WITH-bound field still
disqualifies its whole object, because raw writes from it may run into the
field's siblings.

Conversions follow one invariant: within Pascal code, an address of tracked
heap storage only becomes a raw address through a release. Converting a typed pointer to an
ADRMEM or to a pointer of another target type, and `UNSAFERAW(p)`, release
the referent or elements; a plain EXTERN that turns out to be C releases what
it was handed (above). So any raw address that reaches a typed pointer
(`q := raw`) or descriptor (`UNSAFESUPER(P, raw, lo, hi)`) locates C or other
untracked memory, a released allocation, or an allocation registered with a
different leaf count, all of which read as untracked and initialized; never a
tracked allocation's state under another shape. `UNSAFESUPER` reads its raw
address and bounds and initializes the descriptor value; the elements it
imports are untracked, whatever the import warrants. `RETYPE` converts
integers only. Punning a pointer through variant alternatives is not a
conversion: under INITCK+ the logical-field model rejects reading an
alternative not written as such, and under INITCK- the punned pointer reaches
the allocation's state by leaf position when its leaf count matches, which is
not meaningful (IBM: "not caught").

Files and aggregate I/O. Naming a file is not a read of Pascal data: RESET,
REWRITE, GET, PUT, CLOSE, DISCARD, ASSIGN, EOF, EOLN and the file argument
of READ/WRITE consume control state that the file's own initialization set
(manual 10-3, NEWFQQ), whether the file is a local, a global or a VAR
formal. The buffer variable `F^` of a file whose component type is tracked
(TEXT buffers are CHAR) has per-leaf state allocated beside the buffer, with
the same lifetime, and reached through the file control block, so every
routine the file is passed to sees it. It starts undefined. A successful fill
(GET, RESET's deferred first GET, a TEXT reader taking the next component)
initializes it wholly; EOF, a consumed component, PUT, REWRITE and CLOSE make
it undefined (manual 12-8/9); a write to `F^` initializes what it writes.
Enabled reads of `F^` are checked like other components (`uninitialized
component f^`), a copy out of it follows the strict copy rule (`uninitialized
part of g^`), and PUT consumes the whole component: an enabled PUT requires
every leaf initialized (`uninitialized part of f^`). A buffer handed to an
unmodeled effect (a builtin, a `[C]` VAR) is initialized until its next
transition. A buffer whose component type is untracked (FILE OF REAL, ...) is
the `file buffer` boundary for enabled reads and PUTs. There is no other
aggregate I/O: the typechecker rejects READ/WRITE of typed files ("file
selector must be a TEXT file") and selecting a field of a file buffer
(`g^.a`), so record buffers are written and read whole; codegen rejects WRITE
of an array; strings and sets read or written by READ/WRITE/READSET stay
untracked storage. INPUT and OUTPUT are not identifiers the typechecker
knows, so `INPUT^` is not reachable.

DEVICE code. INITCK is host-only. A DEVICE compiland, CPU-targeted or
NVPTX, has no shadow state, no side channel and no guards, and nothing in
host instrumentation covers it: every enabled read in one is rejected as
`INITCK unsupported boundary: DEVICE code`, whatever storage it names, and
INITCK- there is the ordinary unchecked opt-out. On the host, `LAUNCH` and
`DEVALLOC`, `DEVCOPYTO`, `DEVCOPYFROM` and `DEVFREE` read their operands as
values (grid and block sizes, byte counts, device handles, kernel actuals
copied into launch cells), checked when enabled. Device memory is untracked.
A kernel can reach host storage only through what it is handed: a typed
pointer actual's referent is released at the LAUNCH (the CPU device shares
host memory, and a GPU may too), and a raw address (`DEVCOPYFROM(ADR b, ...)`)
released its variable at the `ADR`. Host descriptors cannot be LAUNCH
arguments at all. Device-side coverage would need its own state, transport
and failure path on the device, which is not planned.

Unsupported boundaries. An enabled read INITCK cannot check is a compile
error, never a silent pass: the compiler prints one line, `INITCK unsupported
boundary: <category> at line L column C` (the consuming token; the location is
omitted for an older AST without coordinates), publishes no IR and stops at
the first such read. Disabling INITCK at that read is the opt-out. Categories:

| Category | Enabled read of | Remedy |
|---|---|---|
| `global or captured storage` | a global (also a pointer dereferenced through one), or an enclosing routine's local | copy into a local; captures are unsupported anyway |
| `untracked type` | storage whose type, or any leaf of it, is outside the slice: REAL, enumerations, subranges, wide integers, ADS pointers, strings, sets, vectors | INITCK- at the read |
| `escaped local or formal` | a local or formal of a tracked type that the routine disqualifies elsewhere: a builtin that writes through it, the `ADR` of a WITH-bound field, a VAR actual of an untracked formal type, a mention under a WITH whose target is not evident | avoid that use, or INITCK- |
| `untracked WITH target` | a field bound by WITH over storage without state (an untracked record, a global, a released heap referent) | as for the target |
| `unresolved WITH target` | a name under a WITH whose target's type cannot be resolved (a function call) | qualify the name |
| `heap storage` | a referent of an untracked type, or one released at this read | INITCK- |
| `file buffer` | `F^` or PUT of a file whose component type is untracked | INITCK- |
| `function result` | an enabled RETURN or closing END of a function whose result type is not tracked | INITCK- at the return |
| `call consumer` | a builtin function outside the modeled ones (ORD, CHR, ODD, ABS, EOF, EOLN, UNSAFERAW, UNSAFESUPER, DEVALLOC) | INITCK- at the call |
| `unsupported expression` | an expression form not modeled, such as a set constructor | INITCK- |
| `selected storage` | selection from a call result (defensive: current source cannot produce it) | none needed |
| `DEVICE code` | any read in a DEVICE compiland | INITCK- |

This is **not whole-program protection** or definite-assignment analysis.
Globals, untracked results, aliases other than tracked VAR/CONST bindings and
WITH over tracked records, untracked or released heap storage, storage
reached through a raw address, ADS pointers, subranges/enums, other
representations, selected storage outside tracked aggregates and all DEVICE
compilands remain excluded. A whole-routine prepass conservatively excludes
locals mentioned in the `ADR` of a WITH-bound field, WITH bodies whose target fields are not
evident, VAR/CONST actuals of untracked formal types,
builtin calls other than output/READ/READLN/scalar builtins, or nested routines
that capture them. This includes escapes after an enabled read and disabled
escapes. Enabled unsupported
consumers are rejected with `INITCK unsupported boundary: <category> at line L
column C` before IR is published (categories above). No blanket lexer warning is issued just for enabling INITCK.
Other producer/consumer paths and alias effects still need their own contracts
and enforcement; do not infer coverage from a
shadow allocation or directive alone. Disabled bad reads are an opt-out, not
safe probes. Missing read snapshots retain the legacy opt-out below.

INITCK defaults to off. An explicit `{$DEBUG+}` also enables it; a subsequent
`{$INITCK-}` overrides that setting. `$PUSH` and `$POP` save and restore the
flag, and `$IF INITCK` tests its metadata value, not compiler support.
Variable declarations snapshot flags at their first token, so a directive
between declarations applies to the following declaration.

Expression factors and designators additionally carry a `read_flags` snapshot
of the full effective flags at their first source token. Calls retain the
callee-token snapshot, not the state after parsing arguments; parentheses
retain the enclosed expression's snapshot. Index selectors snapshot their
first index token and dereference selectors their `^` token, independently
of the base designator. Assignment and WITH targets also retain this metadata
for reads needed to select storage; metadata on a target or a type-only
operand does not classify it as a value read. Typechecking preserves these
objects in place, and codegen receives the snapshots unchanged. Declaration
`meta_flags` are not a substitute for these read-site snapshots. Direct-local
guards use the consumer's own snapshot; broader runtime consumers remain work.

Older JSON AST inputs without `read_flags` remain accepted. An absent snapshot
is a legacy **unchecked** read, not evidence of enabled INITCK. Typechecking
preserves that absence; it does not synthesize snapshots from declaration
`meta_flags`, statement flags, DEBUG, surrounding nodes, or compiler defaults.
Mixed old/new ASTs retain each node's own presence or absence independently.
A guard consumer requires an explicit boolean `read_flags.INITCK`
value of true before treating a read as enabled; absence must never enable a
guard. This compatibility opt-out provides no initialization-safety guarantee.
Regenerate an AST with the current lexer/parser to obtain source read-site
snapshots; merely adding declaration flags cannot upgrade an older AST.

Enabling INITCK directly or through DEBUG is silent when there is no
unsupported enabled consumer. Boundary errors are not suppressed by WARN-.
Other checking switches have independent implementation boundaries; INITCK
initializedness failures are distinct from bounds and pointer-validity checks.

## Enumerated and BOOLEAN I/O

Vintage `WRITE` and `WRITELN` print a user-defined enumerated value as its
numeric ordinal. Vintage `READ` and `READLN` accept a numeric ordinal for that
value. Extended mode writes the member identifier and reads member identifiers
without regard to letter case. These rules apply to standard input and output
and to explicit text files.

`BOOLEAN` keeps its documented vintage behavior in both dialects. Output is
`TRUE` or `FALSE`. Input accepts those names without regard to letter case and
also accepts the numeric ordinals `1` and `0`.

## Wide signed integer input **[extended]**

`READ` and `READLN` accept `INTEGER32` and `INTEGER64` destinations from
standard input or an explicit `TEXT` file. They read signed decimal values
(including an optional `+` or `-`) at their full width; overflow of either
width is a runtime error, never a truncation through vintage `INTEGER` or a
32-bit intermediate. `READLN` first reads its arguments, then consumes through
the next newline. Vintage `INTEGER` and `WORD` readers are unchanged.

Leading whitespace, newlines included, is skipped before the number, as the
vintage `INTEGER` reader does (and as the 1981 manual and ISO texts do with
leading line markers). A newline after a number remains for `READLN` to
consume. Leading zeros are accepted in any number and do not count toward
the length of the number.

At stdin, EOF aborts with `runtime error: unexpected EOF while reading
integer`; a malformed number or out-of-range value aborts with `runtime
error: malformed integer input` or `runtime error: integer out of range`.
For explicit files, malformed input and overflow set `F.ERRS` to 14 when
`F.TRAP` is set (leaving the destination unchanged); without a trap they
abort with the same `runtime error:` messages. EOF aborts in either case,
as in the existing formatted integer reader. Input consumes a decimal prefix
and leaves the following non-digit delimiter for the next read, like the
existing formatted numeric readers.

## String precision

In vintage mode, `::precision` does not limit string output. A string literal,
`STRING` value, or `LSTRING` value writes its full contents. In
`value:width:precision`, the width still pads the full value. The compiler
ignores the precision.

Extended mode uses string precision as the maximum number of characters to
write. The width continues to specify the minimum field width. This rule does
not change numeric formatting. Numeric width and precision have the same
behavior in both dialects.

## READSET and tuning hints

In vintage mode, the final `READSET` argument must be a declared `SET OF CHAR`
value. Extended mode also accepts an anonymous set constructor, such as
`['a'..'z']`. This rule does not remove vintage support for declared sets.

The `{$UNROLL n}` directive requires extended mode or DEVICE code. The count
must be a positive integer. The lexer always records the directive. The
typechecker decides whether the selected dialect permits it.

`[MAXNTID]`, `[REQNTID]`, and `[MINCTASM]` require DEVICE code. DEVICE context
also activates them when the command-line dialect is vintage. These attributes
are valid only on exported kernel procedures. Dimensions must be positive
integer literals. CUDA axis and total-thread limits apply to `MAXNTID` and
`REQNTID`. A kernel cannot have both attributes.

`SYNCTHREADS` is a zero-argument synchronization intrinsic available only in
DEVICE code. In NVPTX compilation it lowers to the block-level hardware barrier
(`bar.sync 0;`), while under host or serial device execution it is a no-op.
Calling `SYNCTHREADS` outside a DEVICE compiland or passing arguments to it is
rejected at typechecking.

A visible user declaration of any predeclared routine name shadows the builtin
in both typechecking and code generation (IBM Pascal, Aug. 1981, p.3-7). The
builtin is only the fallback for an unbound name. Declaration lookup is
case-insensitive, and function-position builtin spellings are also matched
case-insensitively. The statement builtin dispatch remains case-sensitive
(`WRITELN`, `NEW`, `LAUNCH`, and so on), a deliberate deviation from the
manual's general case-insensitivity rather than a gap against the reference.

"Visible" means lexically visible at the call, not merely declared somewhere in
the compiland: a routine nested inside another stops shadowing once its parent's
body ends, and both stages trim their tables at scope exit so they agree on it.

A declaration of any kind shadows, not only a routine. A variable, a parameter,
or a record field a `WITH` statement brings into scope all take the name over,
and calling it is then an error (`Not a function: ORD`) rather than a silent
fall-through to the builtin — the reference rejects the same programs. Only the
statement and expression call paths consult this; the shadowed name remains
usable as the variable or field it is.

Shadowing does not reach a constant expression. `ParseConstant` admits
`WRD`, `BYWORD`, `ORD`, `CHR`, `SUCC`, and `PRED` followed by `(` by name and
nothing else can appear in that position, so `CONST K = ORD('a')` is the
intrinsic whatever else is in scope, matching the reference. A call in ordinary
expression position is not a constant expression and does honor shadowing, so
the same call text can mean the intrinsic in a `CONST` and the user's routine
in a statement.

`VECTOR` types are not available in DEVICE code compiled for NVPTX. Use
scalar kernel code instead. This restriction does not apply to host code or
serial device execution.

`SQRT`, `SIN`, `COS`, `LN`, `EXP`, and `ARCTAN` are not available in DEVICE
code compiled for NVPTX unless the compiland declares its own routine of that
name. That path does not link the host `libm` functions that
implement these builtins, so codegen rejects each one before it emits invalid
PTX. The restriction is keyed on the target, not on DEVICE context: under host
or serial device execution the compiland is an ordinary module in address space
0, links `libm` like any other, and these builtins work normally. `ABS`, `SQR`,
and `FLOAT` remain available everywhere because they use inline operations.

The rejection happens at codegen, not at typechecking, because the typechecker
never receives `--device-triple` and so cannot tell the two device targets
apart. The check applies both to builtin calls and to calls that resolve to a
body-less `[C]; EXTERN` declaration, preventing unresolved `libm` references in
PTX. A user-defined routine with a body shadows the builtin and remains
callable. This is a gap against the reference, which accepts these builtins in
DEVICE code and lowers them to `libm` calls; it applies only when the NVPTX
triple is passed.

`NEW` and `DISPOSE` are not available in DEVICE code. The NVPTX path cannot
link the host `malloc` and `free` functions that implement these operations.
The compiler rejects both operations before it emits invalid PTX.

## GPU (NVPTX) kernels need `{$MATHCK-}` for integer arithmetic **[extended]**

`$MATHCK` is on
by default, and NVPTX code has no way to report a run-time error to the host,
so an integer operation MATHCK would check (`+ - * DIV MOD`, unary `-`,
`SUCC`, `PRED`, signed `ABS`, `SQR`) is a compile-time error there:
`MATHCK unsupported boundary: DEVICE arithmetic at line L column C`, with no
PTX emitted. Put `{$MATHCK-}` at the top of the device implementation (or
around the arithmetic) to get ordinary wrapping arithmetic. Constant
expressions, REAL arithmetic, WORD `ABS` and conversions are unaffected.
`DIV`/`MOD` stay unavailable on NVPTX under either setting, because their
zero-divisor failure also needs a host path. TRUNC/ROUND saturate on NVPTX
instead of failing. CPU (serial) DEVICE code shares the host failure path and
gets the same checks as host code, including inside `LAUNCH`ed kernels.

```pascal
(*$INCLUDE:'vadd.inc'*)
{$MATHCK-}   { required: integer arithmetic below would otherwise be rejected }
DEVICE IMPLEMENTATION OF vaddu;
PROCEDURE add(a, b, c: ADS(GLOBAL) OF BUFFER; n: INTEGER32);
VAR i: INTEGER32;
BEGIN
  i := THREADIDX_X + BLOCKIDX_X * BLOCKDIM_X;   { wraps; never checked }
  ...
```

Without the directive this kernel (`tests/optional/gpu/vadd.pas`) fails to compile
with `MATHCK unsupported boundary: DEVICE arithmetic at line L column C`,
pointing at the first operation MATHCK would check, and no PTX is emitted. This is
the deliberate [DEVICE boundary policy](#mathck-vector-device-and-unsupported-boundaries),
not an oversight: a check the compiler cannot
enforce on the GPU is never silently dropped. Overflow in such a kernel wraps
at the type's width with no diagnostic, so validate index ranges on the host
or run the kernel as CPU DEVICE code (which is checked) while debugging.

## Vectors (SIMD) **[extended]**

`VECTOR [n] OF T` is a fixed-width SIMD vector, lowered to an LLVM `<n x T>`.
It is a first-class type: declare it, assign it whole, pass it to and return
it from a routine, take its `SIZEOF` / `LOWER` / `UPPER`.

- **Host and serial-device only.** The compiler rejects `VECTOR` in a compiland
  that targets NVPTX. NVPTX is SIMT, so vector arithmetic becomes one scalar
  operation per lane and consumes registers without providing SIMD execution.
  Use scalar code in NVPTX kernels.
- **`VECTOR` is a contextual keyword.** It is a type only when followed by
  `[`; anywhere else it is an ordinary identifier and existing code keeps
  working. `PACKED VECTOR` is rejected.
- **Lane count `n`** is a constant expression (integer literal or a `CONST`
  integer identifier — the same two forms a vector's or array's bound
  accepts) that must fold to a **power of two in 2..64**.
- **Element type `T`** must be a scalar: an integer-family type,
  `REAL` / `REAL32`, `BOOLEAN`, or `CHAR`. Not a record, array, or vector.
- **A `VECTOR [n] OF BOOLEAN` is a mask.** It is stored as `<n x i8>` with
  one `0`/`1` per lane, not `<n x i1>`. Comparisons (`=`, `<`, …) between two
  vectors produce a mask; `VSELECT(mask, a, b)` blends lanewise;
  `VANY(mask)` / `VALL(mask)` reduce it to a `BOOLEAN`.
- **Operators are elementwise** and require *both* sides to be the identical
  `VECTOR` type — there is no scalar promotion. Use `VSPLAT(x, V)` to build a
  vector from a scalar. Arithmetic (`+ - * /`, `DIV`, `MOD`), bitwise on
  integer vectors (`AND`, `OR`, `XOR`, `NOT`), unary `-`, and the horizontal
  reductions `VSUM` / `VPROD` / `VMIN` / `VMAX` (to a scalar element) are
  available. Float `VSUM` / `VPROD` are ordered.
- **Integer lanes follow MATHCK.** Under MATHCK+ (the default), lane `+ - *`,
  unary `-`, `VSUM` and `VPROD` are checked per lane at the element type and
  fail with the scalar `runtime error: MATHCK ...` diagnostic (`VSUM`/`VPROD`
  name themselves and report the partial result and lane). A checked
  operation is one SIMD overflow test and a single branch, and only a
  failing operation is replayed lane by lane to name the lowest failing lane.
  `{$MATHCK-}` around hot vector code restores the single wrapping SIMD
  instruction with no test. Lane `DIV`/`MOD` are
  always lowered per lane with the scalar zero-divisor failure and safe
  `MIN DIV -1`, under either setting.
- **`v[i]`** reads and writes one lane. **`VLOAD(arr, i, V)`** and
  **`VSTORE(arr, i, v)`** move `n` contiguous elements `arr[i .. i+n-1]`
  between an `ARRAY OF T` and a vector (`T` must match exactly; a `BOOLEAN`
  mask has no memory form and is rejected). `arr` is an array variable or
  any array-typed designator — `p^`, `r.buf^`, `r.fixed_arr` — addressed in
  place, never copied. Evaluation order is array address, index, (for
  `VSTORE`) value, then the bounds check, then the memory access.
- **Fixed-bound arrays: constant indices only.** A constant `v[i]` or a
  constant `VLOAD` / `VSTORE` offset whose lanes leave the declared range
  is a compile error; a variable vector-lane/transfer index is unchecked.
  This vector policy is separate from scalar fixed-array `$INDEXCK`.
- **`SUPER ARRAY`: whole-lane-range run-time check.** The operand must be
  pointee of a host descriptor pointer (`p^`, including selected fields,
  array slots and aliases). Its upper bound travels in the descriptor,
  including through native calls/results and explicit unsafe imports; no
  pre-data header is read. Once, before any lane is loaded or stored, the compiler checks
  `p <> NIL`, `i >= LOWER(p^)` and `i + n - 1 <= UPPER(p^)` in 128-bit
  arithmetic (a `WORD` index is unsigned), and on failure prints
  `runtime error: VLOAD|VSTORE index I with N lanes is outside array bounds
  LO..HI` (or `... through a NIL pointer`) to stderr and calls `abort()`.
  A constant index below the static lower bound is still a compile error.
  A bare `SUPER ARRAY` variable, a VAR parameter, an `ADS` pointee, or any
  DEVICE-code operand has no run-time bound and is rejected at compile
  time. Not detected: a dangling pointer after `DISPOSE`, inaccessible storage
  or a false capacity/lifetime warranty at unsafe import.
- **The type-name argument** (`VSPLAT`, `VLOAD`, `VSTORE`) names a declared
  `VECTOR` type; it is not an expression.
- **ISA selection** is `--target-cpu` / `--target-features` on the driver
  (attached as LLVM function attributes; default is baseline x86-64). No
  `llvm.x86.*` intrinsics, no runtime CPU detection.
- **Not usable in the compiler's bootstrap sources.** `gen1` is built by
  `pasboot`, whose bootstrap subset has no `VECTOR`; no file that `gen1`
  compiles may use the syntax. See
  [`bootstrap_subset.md`](bootstrap_subset.md).

## BOOLEAN set constructors **[native]**

Both dialects accept BOOLEAN values in a set constructor. A value can be
`FALSE`, `TRUE`, a BOOLEAN variable, or a named BOOLEAN constant. BOOLEAN
range endpoints also work. `[FALSE..TRUE]` contains ordinals 0 and 1.
`[TRUE..FALSE]` is empty. The compiler evaluates each element and each range
endpoint once before it adds bits. An evaluated union such as
`bs := bs + [TRUE]` works when `bs` is a `SET OF BOOLEAN`.

The set still uses a 256-bit bitvector. An anonymous constructor keeps the
generic INTEGER bounds 0..255. Thus, mixing a declared BOOLEAN set with a
constructor in a set operation does not retain BOOLEAN bounds.

## Set base compatibility **[native]**

Sets are compatible when their ordinal hosts agree: INTEGER, CHAR, BOOLEAN,
or the **same enum declaration**. Aliases and subranges keep their host;
distinct enums with identical ordinals do not become interchangeable. All
constructor elements and both range endpoints must agree on a host, even
when a range is reversed. The empty constructor `[]` is unconstrained.
Assignment, value arguments/results, comparisons, union/difference/
intersection and `IN` check hosts before code generation. The stricter
VAR-parameter identity and lvalue rules remain. A same-host ordinal outside
a set's declared range gives FALSE for `IN`, not a type error. Both dialects
support enum sets over a named enum, its alias/subrange, or enum endpoints;
constructor enum values and membership use their ordinal values (0..255).
The ABI remains a 256-bit bitvector with BOOLEAN values zero-extended;
set operands are evaluated once in left-to-right order. Anonymous
constructors and any operation mixing one in keep generic INTEGER 0..255
`LOWER`/`UPPER` bounds, regardless of their semantic host; compatible
declared-set operations widen their bounds.

This is **host compatibility**, not the separate rule that every member
assigned to a declared set fits its *declared* base range (IBM diagnostic
2181, `$RANGECK`); that value-range check is deferred. PACKED set
compatibility is also deferred: the parser discards PACKED on set types and
the representation is unchanged. `SET OF WORD` still shares codegen's
INTEGER representation despite distinct semantic identities; the manual's
INTEGER-constant-to-WORD exception needs separate treatment. Wide integer
set bases/membership and compile-time diagnostics for constant ordinals
outside the 0..255 representation are not implemented. The existing runtime
0..255 constructor guards remain, including their reversed-range and
device-code exclusions.

## Set constructor element range **[native]**

A set holds ordinals 0..255. Each element of a set constructor, and each
endpoint of a nonempty range, must be in 0..255. If one is not, the program
stops with `runtime error: set element V is outside 0..255`. The compiler
does this check even for a constant element such as `[300]`, and even when
`$RANGECK` is off. A reversed range such as `[300..0]` is empty, so the
compiler does not check its endpoints. Device code does not do this check.

## BOOLEAN membership **[native]**

Both dialects accept a BOOLEAN value on the left of `IN`, for example
`TRUE IN bs` or `flag IN [FALSE..TRUE]`. The compiler zero-extends the value
before the bit test, so `FALSE` is ordinal 0 and `TRUE` is ordinal 1. It
evaluates the left operand once and then the right operand once. This
left-then-right order is a native choice; the 1981 manual does not specify
it. The left operand of `IN` must be an INTEGER, CHAR, BOOLEAN or supported
enum value compatible with the right set's host. WORD and wide integers
remain unsupported.

As the 1981 manual allows, the left operand can be outside the range of the
set's base type. Then the result is FALSE. This includes a value outside
0..255, such as -1 or 300, which cannot be in any set.

## AND THEN and OR ELSE **[both]**

As the 1981 manual says (Sequential Control Operators), `AND THEN` and
`OR ELSE` can join only the operands of an `IF`, `WHILE` or `UNTIL`
condition. They cannot occur in parentheses or in any other expression,
such as an assignment, an actual parameter or `NOT (...)`. They bind more
loosely than every other operator and are evaluated from left to right, so
`IF W AND THEN X OR ELSE Y AND THEN Z` means `((W AND THEN X) OR ELSE Y)
AND THEN Z`. A right operand that the left one decides is not evaluated.
The parser rejects any other use with `Parser Error: AND THEN/OR ELSE can
only join the operands of an IF, WHILE or UNTIL condition, not in
parentheses or another expression`. `pretty81` prints a chain without
parentheses, so its output parses again.

## Host SUPER ARRAY descriptor ABI **[native]**

- [Storage and identity](#descriptor-storage-and-identity)
- [Native transport](#descriptor-native-transport)
- [Unsafe raw boundary](#descriptor-unsafe-raw-boundary)
- [Allocation and checked access](#descriptor-allocation-and-checked-access)
- [Evidence and limits](#descriptor-evidence-and-limits)

### Descriptor storage and identity

Host `^SUPER ARRAY` values use nonpacked LLVM `{ptr, i64}` storage on the
supported x86-64 Linux/SysV target: data at offset 0, actual inclusive upper
(signed INTEGER64) at offset 8, size/array stride 16, alignment 8. Data points
to the first element at the declared lower index; there is **no pre-data bound
header**. The declared lower, ordinal domain and element identity are immutable
type metadata. Enclosing aggregates use natural padding. Other host targets
require a new layout/ABI audit.

Rebuild affected units, callers and callees together; old objects are incompatible.
The break includes slots, enclosing records, array strides, SIZEOF, typed-file
element layouts and parameter/results. Descriptor-containing binary data is
process-local memory representation, not portable serialization or a safe
reconstruction mechanism. Arbitrary bytes supply no validity, ownership or
lifetime guarantee.

NIL is `{null, 0}`; its upper is not a bound. NIL tests and equality/inequality
compare data only, not upper. Ordering/arithmetic are rejected. Bounds do not
prove liveness; DISPOSE does not invalidate aliases or detect dangling access.
Assignment, arguments and results require the same resolved pointer identity,
including aliases (`TYPE Q = P`), referent, lower/domain and pointer flavor/space.
Separate declarations are not interchangeable merely because layouts match;
use a shared named pointer type in fields and repeated routine headings.
Reference actuals need matching descriptor storage. Ordinary thin-pointer rules
are unchanged. NIL literals coerce to the whole descriptor; arbitrary zero
ADRMEM values do not.

The i64 carrier does not broaden source domains or introduce INTEGER64/WORD64
declared-lower syntax. INTEGER, WORD, CHAR, BOOLEAN and enum/subrange domains
retain their limits. Both compiler phases resolve lower/domain consistently;
unsupported/unresolved domains are rejected, not defaulted to INTEGER. NEW and
unsafe import require domain-valid upper >= lower, representable as signed i64;
wider expressions are checked before narrowing (WORD64 above INT64_MAX cannot
wrap into a bound). LOWER/UPPER return INTEGER64: LOWER is type-only, UPPER
selects once and diagnoses final NIL before using upper.

### Descriptor native transport

Assignment, aliases, record/array slots, parameter temporaries and result slots
load/store the complete value. The explicit SysV aggregate machinery uses two
INTEGER-class eightbytes: value arguments use two i64 coercion pieces, results
use `{i64, i64}`, while storage stays `{ptr, i64}`. Reference modes pass one
address of the complete slot, not element data. Recursively classify both leaves
in aggregates; register accounting, MEMORY/byval and sret rules apply. Signatures,
call marshalling, callee and return reconstruction must agree; LLVM struct
spelling alone does not establish the object ABI.

For `record.p^[i]` and `a[j]^[i]`, the shared designator carries the selected
pointer's descriptor separately from element data, never a declaration-wide
last allocation. UPPER, scalar indexing and VLOAD/VSTORE consume that actual
bound source. Vector transfer-check policy remains independent of scalar INDEXCK.
Borrowed non-pointer SUPER ARRAY formals remain unsupported.

DEVICE storage/lowering stays thin, including DEVICE interfaces spliced into
host modules. Imported host descriptor parameters/results/storage are rejected
in DEVICE code, not reinterpreted as thin pointers; opaque raw-only interfaces
remain usable.

### Descriptor unsafe raw boundary

Extended intrinsics respect normal builtin shadowing:

- `UNSAFERAW(p)` returns CPTR/ADRMEM, extracting data only, not slot storage.
  It evaluates p once; NIL exports null.
- `UNSAFESUPER(P, raw, lower, upper)` returns descriptor type P. P is a type
  argument as in RETYPE and must resolve to a supported host super-array pointer.
  Raw may be CPTR/ADRMEM or a compatible thin host element pointer, not integer,
  ADS or another descriptor. Runtime operands run once; relative order is
  unspecified.

Import validates matching declared lower, domain-valid/representable upper >=
lower, nonnull data, element alignment and nonoverflowing count/stride/byte-span/
address arithmetic. Widen before narrowing. These checks apply under INDEXCK-
too, never dereference raw or inspect raw-8, and fail deterministically without
returning/publishing a value. Use NIL assignment, not null import. Runtime failure
texts are pinned by the [descriptor probes](testing/descriptors.md#host-descriptor-contracts).

Validation establishes metadata/arithmetic validity, **not accessible capacity,
provenance, ownership or lifetime**. The caller warrants contiguous storage of
the stated extent, valid elements, permitted read/write access and sufficient
lifetime. Nonnull/aligned addresses prove neither allocation origin nor capacity.
C raw results require explicit import before checked or unchecked descriptor use.
Import grants no ownership. DISPOSE of an import/alias is valid only with the
exact native allocation/free contract and exclusive right to free; borrowed
C/stack storage fails that precondition. No compile/runtime misuse detection is
promised: two-word descriptors cannot enforce ownership through arbitrary aliases.

Both intrinsics emit stable `unsafe-super-array-conversion` warnings;
warning-as-error control syntax is deferred. Vintage and DEVICE uses are rejected.
Implicit conversions to/from ADRMEM, CPTR, thin pointers or ADS (including RETYPE,
address arithmetic and numeric READ/WRITE) are rejected. Explicit raw export can
print an address; numeric input cannot reconstruct a descriptor.

C arguments/results containing descriptors are rejected recursively, including
VAR slots and enclosing value/reference aggregates. Statically visible opaque
address escapes to descriptor-containing storage, including ADR of a slot or
aggregate, are rejected; ADR of a non-pointer SUPER ARRAY referent awaits a
borrowed-view contract. ADR(slot) is not element export. Arbitrary raw-memory
operations remain unsafe: pointer spelling cannot prove what an address hides.
Direct descriptor LAUNCH arguments and ADS conversions are rejected.
DEVCOPY/DEVFREE require explicit raw export where applicable; copying descriptor
bytes neither converts DEVICE representation nor transfers ownership.

### Descriptor allocation and checked access

NEW evaluates destination selection and upper once, validates bounds/domain,
count, size and alignment, allocates directly, then publishes one full descriptor.
Checks apply under INDEXCK- too. `pas_super_new` uses 128-bit arithmetic; it rejects
WORD64 upper > INT64_MAX, upper < lower or outside domain, count > SIZE_MAX,
bytes > SIZE_MAX or PTRDIFF_MAX, and NULL malloc. Failures abort with
`runtime error: NEW SUPER ARRAY <reason>`; [NEW probes](testing/descriptors.md#descriptor-new-and-index-probes)
pin the reasons. The helper has no destination address; only success reaches the
compiler's store. Selection/bound side effects are not rolled back. Transactional
publication is **not atomicity or a concurrent-access guarantee**, and does not
require element zero-initialization.

Strides/alignment use LLVM allocation layout, not narrow SIZEOF arithmetic.
Array layouts beyond signed host size are rejected before an overflowing LLVM
layout query; records retain 32-bit field-offset limits. Nested non-pointer SUPER
ARRAY elements have no static extent and are rejected. These checks also govern
unsafe-import spans. NEW elements aligned beyond 16 bytes are rejected. Allocation
must return the exact recoverable base compatible with free; no adjusted data
pointer without a free base. DISPOSE frees that unchanged base, not a header.
Ordinary thin-pointer NEW also aborts with `runtime error: NEW allocation failed`
(IBM error 2001, "No Room In Heap") before destination publication, not by storing NIL.

Host `$INDEXCK+` compares the scalar index in widened signed/unsigned i128 against
declared lower and the selected descriptor's upper before offset/GEP/data access,
using `pas_array_index_error` and the same fixed-array diagnostic with actual
lower..upper. The index runs once; even a checked constant bad index fails only
when executed. Offset/GEP reuses that checked full-width value. A NIL descriptor
fails via `pas_super_index_nil_error` (`runtime error: index through NIL
super-array pointer`) before bounds comparison/address formation, independent
of index value. The index expression runs once, but its side-effect ordering
relative to NIL failure is deliberately not pinned down.

Per-index snapshots apply; in-expression directives affect subsequent indexes
only. INDEXCK- suppresses scalar guards, not descriptor transport or import/NEW
validation. Borrowed non-pointer subscripts are rejected outright; DEVICE has no
such guard. Guards never inspect a pre-data header or make a dangling alias safe.

### Descriptor evidence and limits

[IBM Pascal Compiler, August 1981](https://www.bitsavers.org/pdf/ibm/pc/languages/IBM_Pascal_Compiler_Aug81.pdf),
printed pp. 6-43 (descriptors), 6-35 (address without bounds), 6-29–6-31
(pointer identity/operations), 6-15–6-16 (bounds/NEW), 10-16–10-17 (returns),
provides historical context. Local OCR `IBM_Pascal_Compiler_Aug81_djvu.txt` lines
7943–7963, 7593–7604, 7325–7396, 6636–6701 and 11000–11058 respectively were not
verified against scan images. Historical widths, 16-bit bounds and return
registers are **not** the native ABI.
[LLVM LangRef](https://llvm.org/docs/LangRef.html) supports aggregate operations
and DataLayout padding, not atomic publication or C ABI from struct spelling.
Signed i64 bounds, equality-by-data, unsafe syntax/ownership and deterministic
failures are local decisions, not historical parity. Borrowed formals, DEVICE
descriptors and temporal safety remain deferred. See the
[coverage map](testing/descriptors.md#host-descriptor-contracts) for test entry points.

## Bound expressions **[native]**

`LOWER(expression)` and `UPPER(expression)` accept the 1981 manual's array,
set, enumerated and subrange operands, subject to these native ABI limits:

| Operand type | LOWER | UPPER | Evaluation |
| --- | --- | --- | --- |
| host `^SUPER ARRAY` final dereference, including indexed/record designators and pointer-valued function call results such as `f(x)^` | declared lower bound | actual selected descriptor's upper bound | UPPER evaluates selection exactly once; LOWER does not evaluate |
| fixed array | declared lower | declared upper | type only |
| `STRING(n)` / `LSTRING(n)` | 1 / 0 | capacity `n` (not current length) | type only |
| `VECTOR[n] OF T` (local extension) | 0 | `n-1` | type only |
| set | ordinal base type low | ordinal base type high | type only |
| enumerated | first member ordinal | last member ordinal | type only |
| subrange | declared low | declared high | type only |

The result type for static set, enumerated and subrange bounds is the base
ordinal type (for example, `LOWER(e)` for an enum is an enum value, and
`LOWER(SET OF BOOLEAN)` is BOOLEAN). Fixed-array bounds use their declared
index type, including CHAR and enum index types. The established STRING,
LSTRING and VECTOR bound results remain INTEGER; dynamic super-array bounds
remain INTEGER64. A set constructor without a declared base uses the local
generic SET representation (`INTEGER` index bounds 0..255). A set union,
intersection or difference whose operands share a base type keeps that base,
with bounds that cover both operands' declared ranges (`UPPER(bs + bs)` is
TRUE for a `SET OF BOOLEAN`, and `SET OF 3..9 + SET OF 1..5` has bounds
1..9); mixing in a constructor gives the generic set. Incompatible bases
are rejected by the typechecker rather than producing generic bounds. A
named set value or function result retains its declared bounds, including a
parameterless function named without an argument list (`UPPER(getset)`). String literals have no declared fixed capacity and are
rejected as bound operands.

Static operands and `LOWER` use **only the type, not the value**, and never
execute their index/call side effects. Dynamic `UPPER` evaluates a selected
pointer, index or function call once, then uses that descriptor's upper. A NIL
selected pointer produces `runtime error: UPPER through NIL super-array pointer`
before treating its upper as an array bound; `LOWER` of the same NIL pointer stays type-only.
This defined NIL check intentionally changes the old unchecked `UPPER(p^)`
behavior. Dangling pointers after `DISPOSE` are not detected.

A type identifier (unlike `SIZEOF`), an undereferenced pointer, a non-pointer
super-array value without a supported dynamic-bound ABI, and arithmetic or
literal expressions outside the permitted types are rejected. Standalone
subrange type declarations are supported for vintage INTEGER bounds within
`-32768..32767`, CHAR, BOOLEAN, and a pair of members from one enumerated
type; stores into them are range-checked as described under
[Subrange range checks](#subrange-range-checks-native). Function call
postfix selectors are supported only inside a bound operand; this does not
make `f(x)^` a general expression elsewhere. Pointer descriptor formals preserve
bounds; borrowed non-pointer super-array formals are explicitly rejected until
their separate view ABI is implemented. The manual does not prescribe this
implementation's NIL diagnostic or side-effect count.

The earlier Python parser accepts only `identifier ["^"]` here. Field,
indexed and call-result selectors, and general expression operands are
native-only.

## Subrange range checks **[native]**

Under `$RANGECK`, which is on by default, a value stored into a subrange
(an `INTEGER`, `CHAR`, `BOOLEAN` or enumerated one, named or anonymous)
must lie inside its declared bounds. Otherwise the program stops with

    runtime error: value 12 is outside subrange 0..9

on stderr and aborts (exit status 134), like the other runtime range
errors. The value and bounds are ordinals: a `CHAR` subrange reports
character codes and an enumerated one reports member positions.

The check covers:

- assignment to a subrange variable, record field, array element or
  pointee, and to a function's subrange result inside its body;
- a value parameter of subrange type (a `VAR` parameter is not checked,
  because its actual must already have the same type);
- `READ`/`READLN` into a subrange, from stdin or a text file, and a
  subrange program parameter. A trapped file read failure, which leaves the
  variable unchanged, is not checked;
- a `FOR` loop over a subrange control variable: if the loop runs at all,
  its initial and final values must both be in range, and the check is made
  once, before the first iteration. A loop that runs zero times is not
  checked.

The check is made on the value before it is narrowed to the subrange's
storage width, so a wide value cannot wrap into range. A constant that is
out of range is reported when the store runs, not at compile time.
Arithmetic is not checked itself; its result is checked when it is stored.
`SUCC` and `PRED` are checked at the call: stepping a CHAR, BOOLEAN or
enumeration value past its first or last value fails, and so does a result
outside the declared bounds of a subrange variable or designator argument.

`{$RANGECK-}` turns the check off for the statements that follow it, and
`{$RANGECK+}` turns it back on. Every statement records the setting at its
first token, including `FOR` and `CASE` (not after its END). Expression
consumers, including function calls in conditions and SUCC/PRED, use their
own first-token `read_flags` snapshot. Codegen scopes and restores this
context around every statement and expression: nested actuals, branch
bodies and earlier siblings cannot toggle an enclosing operation's checks.
A directive inside FOR bounds or call actuals therefore does not
retroactively alter the FOR/call policy. Legacy AST nodes without the
snapshot inherit the enclosing scoped context; the root defaults to on.
CASE's enabled no-match trap is implemented;
FOR's existing nonempty-loop endpoint/publication policy is unchanged.
Regression: `tests/contract/rangeck_scope.sh`. Array
indexes are not checked by `$RANGECK` (see `$INDEXCK` below). Host `CONCAT`
capacity checking is described below; other string-capacity paths remain
unchecked. NVPTX `DEVICE` code has no host-runtime subrange or CONCAT check;
a `DEVICE` compiland targeting the CPU follows the host `$RANGECK` path.

#### CONCAT capacity checks **[native]**

Under `$RANGECK+` (on by default), `CONCAT(t, s)` evaluates its source once,
then checks the combined length in widened arithmetic before copying any
characters or updating `t`'s length byte. The maximum accepted length is
`min(declared capacity, 255)`: even bare `LSTRING` (capacity 256) cannot
represent length 256 in its byte. Overflow flushes stdout, reports

    runtime error: RANGECK CONCAT length V exceeds capacity CAP at line L column COL

on stderr, flushes stderr and aborts (normally status 134 on Linux). Here
`capacity` is the effective maximum above; the final column value is the
source coordinate. Compiler-generated destination bytes stay unchanged on
failure; source-expression side effects are not rolled back. Exact-capacity,
empty-source and self-append calls work normally.

The CONCAT statement's first-token snapshot owns the check, not directives
inside its source expression. Legacy statements inherit scoped RANGECK and
report 0/0 if location is absent. `$RANGECK-` emits no capacity guard: invalid
unchecked appends may corrupt memory or wrap the length byte. This is not
unconditional memory safety, does not affect MATHCK, and does not add checks
to assignment, value parameters, COPYLST/COPYSTR/INSERT or raw length-byte
writes. CPU DEVICE uses the host check; NVPTX retains its existing unchecked
boundary without calling host diagnostics. Regression:
`tests/contract/rangeck_concat.sh`.

### Fixed-array index checks (`$INDEXCK`) **[native]**

`$INDEXCK` defaults to on. The native parser snapshots it at the first token
of **each** index expression (after `[` or a dimension comma), including indexes
in assignments, calls, conditions, loops and nested selectors. The snapshot
survives typechecking and a legacy AST without it defaults to on. `{$INDEXCK-}`
disables subsequent snapshots and `{$INDEXCK+}` restores them, independently of
`$RANGECK`; a directive later within an index expression does not change that
index's snapshot, but does affect subsequent indexes.

On host programs, an enabled snapshot guards a fixed `ARRAY [lo..hi] OF T`
selector before computing its offset/address or accessing memory. This covers
reads and writes through ordinary arrays, nested dimensions, record fields and
pointers. It also guards a host descriptor-backed `SUPER ARRAY` scalar
subscript against the selected descriptor's declared lower and actual dynamic
upper (the type table's high bound is a placeholder), reusing the same
diagnostic with the actual upper printed as `HI`; a borrowed non-pointer
super-array subscript is rejected rather than guarded, and `$INDEXCK-`
suppresses the super-array guard as well. Each index expression runs once. A
checked out-of-range index,
including a constant, fails **when the access runs**, not at compile time: the
runtime flushes stdout, prints

    runtime error: array index V is outside bounds LO..HI at line L column C

to stderr using the original signed or unsigned index value (including 64-bit
values) and the declared bounds, flushes stderr, then aborts (normally status
134 on Linux). Coordinates identify the first token of the index expression,
including each comma-separated dimension. The selector's `op_location` is
preserved through typechecking; missing legacy coordinates report `0:0`,
without changing the default-on legacy guard. File/include identity is not
part of this diagnostic ABI. `pas_array_index_error` now takes trailing
line/column arguments; rebuild old compiled callers with the updated runtime.
`tests/contract/indexck_diagnostics.sh` checks
fixed/SUPER loads and stores, nested indexes, exact once-only evaluation,
legacy/mixed metadata and disabled IR in both dialects at O0–O3.
An unchecked constant or variable index emits no fixed-array
guard; this does not make an out-of-bounds access safe. `$RANGECK` does not
control array indexes. Integer-family indexes are widened with their own
signedness before lower-bound subtraction even when checking is disabled;
legal high-bit unsigned indexes and full-span signed offsets therefore retain
correct addresses without guards. This also applies to DEVICE address arithmetic,
without adding host diagnostics there.

This INDEXCK slice does **not** add checks to `STRING`/`LSTRING` subscripts,
or the capacities of `COPYLST`, `COPYSTR` and `INSERT`. `CONCAT` has the
separate RANGECK capacity contract above. Nor does INDEXCK
change `VECTOR` lane indexing or the super-array guard's interaction with
`VLOAD`/`VSTORE`: constant out-of-range vector
lanes and fixed-array vector transfers retain their compile-time diagnostics;
variable vector lanes and fixed-array transfer offsets do not use `$INDEXCK`.
`VLOAD`/`VSTORE` through a `NEW`-allocated super-array pointer retain their
separate whole-lane-range runtime check (see [Vectors (SIMD)](#vectors-simd-extended)).
`DEVICE` compilands, whether CPU-targeted or NVPTX, do not get this host
fixed-array runtime guard. The Python reference AST does not carry the native
`indexck` snapshot.

This is a deliberate **local fixed-array subset**, not exact IBM parity. The
[IBM PC Pascal Compiler (August 1981)](https://www.bitsavers.org/pdf/ibm/pc/languages/IBM_Pascal_Compiler_Aug81.pdf)
uses `$INDEXCK` for super arrays too and diagnoses a constant out-of-range
array index at compile time (error 198). [Pascal/VS](https://www.bitsavers.org/pdf/ibm/370/pascal/SH20-6168-1_Pascal_VS_198112.pdf)
uses `%CHECK SUBSCRIPT` instead and includes string subscripts. Neither
historical contract implies that the unchecked cases above are safe.

## Named ordinal array index types **[native]**

The 1981 manual (printed pp. 6-11/6-12, 10-3) says a fixed array's index
type is ordinal and shows `ARRAY [COLOR]` and `ARRAY[INDEX] OF REAL` with
a named subrange. The native compiler now accepts a bare ordinal type name
in the brackets, and it lowers to **exactly** the array the spelled-out range
would give — same bounds, element count, index representation, `LOWER`/
`UPPER` result types, and `$INDEXCK` guard domain:

```pascal
TYPE Color = (red, green, blue);
     Shade = Color;          { an alias resolves to Color's domain }
     Small = green..blue;    { 1..2, an enum subrange }
     Index = 2..4;
VAR a: ARRAY [Color] OF INTEGER;    { same as ARRAY [red..blue] }
    b: ARRAY [Shade] OF INTEGER;    { alias of the enum }
    c: ARRAY [Small] OF INTEGER;    { 1..2, not INTEGER's full range }
    d: ARRAY [Index] OF REAL;       { 2..4 }
    e: ARRAY [BOOLEAN] OF INTEGER;  { FALSE..TRUE, TRUE is ordinal 1 }
    f: ARRAY [WORD] OF INTEGER;     { 0..65535, LOWER/UPPER are WORD }
```

The name must be a **type**: a `CONST` or variable identifier in the
brackets is a typecheck error (`Array index requires a type name, not a
value: V`), as are an undeclared name (`Unknown type name`) and a
non-ordinal type such as `REAL` or a `RECORD` (`Array index type must be
ordinal`). A named array index whose subrange bounds are reversed
(`TYPE Bad = 4..2; ARRAY [Bad]`) is rejected at typecheck
(`Array index type has reversed ordinal bounds`); a bare reversed
subrange declaration outside array-index position is caught by codegen. `INTEGER64`/`WORD64` domains are rejected as unrepresentable
by the typechecker; `INTEGER32`/`WORD32` pass it (the type is ordinal with
knowable bounds) and are rejected by codegen as
`codegen: array index domain is too large` — the lowering cannot build a
2^32-element fixed array. A `SUPER ARRAY` still requires the explicit
`lo..*` form, and `PACKED` arrays remain unsupported.

The index **expression** contract is unchanged from explicit ranges: the
expression must be ordinal (a `REAL` or string index fails
`Array index must be an ordinal type`), but kind identity is not enforced —
`e[1]` into the BOOLEAN array above compiles exactly as `ARRAY
[FALSE..TRUE]` indexed by `1` does, and the `$INDEXCK` runtime guard holds
the domain.

## MATHCK: integer overflow and division checks **[both]**

`$MATHCK` is implemented. It is on by default (and through `$DEBUG`), so an
ordinary program gets these checks without asking. This section is the
canonical MATHCK contract. Rules are normative; paragraphs marked
*Implementation* locate the current lowering and may change without changing
the rules. The [test map](testing/mathck.md#mathck-test-map) names the
focused regression for each rule, and the persisted
[G1–G29 inventory](testing/mathck.md#mathck-gap-baseline) is a classification
audit, not evidence that checks are missing. Compiler-source arithmetic and the
pasboot policy (it accepts but ignores MATHCK) belong to the
[bootstrap contract](bootstrap_subset.md#self-hosting-arithmetic).

- [Operation scope](#mathck-operation-scope)
- [Overflow definition](#mathck-overflow-definition)
- [Disabled MATHCK semantics](#disabled-mathck-semantics)
- [Constant operations](#mathck-constant-operations)
- [Directive snapshots](#mathck-directive-snapshots)
- [Legacy AST compatibility](#mathck-legacy-ast-compatibility)
- [Interaction with RANGECK](#mathck-and-rangeck)
- [Runtime diagnostics](#mathck-runtime-diagnostics)
- [Builtin classification](#mathck-builtin-classification)
- [VECTOR, DEVICE and unsupported boundaries](#mathck-vector-device-and-unsupported-boundaries)
- [Outside MATHCK](#outside-mathck)
- [Differences from IBM](#explicit-mathck-differences-from-ibm-pascal-1981)

### MATHCK operation scope

MATHCK governs explicitly evaluated INTEGER-family and WORD-family arithmetic
at every scalar width: `INTEGER8`, `INTEGER`, `INTEGER32`, `INTEGER64`,
`WORD8`, `WORD`, `WORD32` and `WORD64`.

| Operation | Checked condition |
|---|---|
| Binary `+`, `-`, `*` | Overflow |
| Binary `DIV`, `MOD` | Division by zero (under either setting) and applicable overflow |
| Unary minus | Overflow |
| `SUCC`, `PRED` | Base-type endpoint overflow |
| `ABS`, `SQR` | Overflow |
| Integer VECTOR lanes, `VSUM`, `VPROD` **[extended]** | The scalar rules per lane; each reduction step |

An enabled in-scope operation is either checked or rejected at compile time
(see [unsupported boundaries](#mathck-vector-device-and-unsupported-boundaries));
accepting it silently without a check is not a supported implementation
strategy. Every listed scalar width is checked, so wide scalar arithmetic is
not a boundary.

Type admission and promotion are separate from checking. Operands of
different widths in one family widen to the wider operand, which is the result
type and the checked width (`INTEGER32 * INTEGER` is checked at 32 bits).
Nonconstant mixed INTEGER-family/WORD-family operands are rejected (G24; see
[Integer constants and context](#integer-constants-and-context)). Listing
SUCC/PRED here does not move their CHAR, BOOLEAN, enumeration or subrange
domains out of RANGECK.

FOR-loop control is not a MATHCK operation. The loop terminates at its final
value without stepping past it under either setting, so a loop ending at
`32767` or `65535` terminates normally: MATHCK+ must not turn it into an
overflow error, and MATHCK- must not let the endpoint step wrap into an
infinite loop. Explicit arithmetic in the bounds or the body is ordinary
in-scope arithmetic.

Compiler-generated bookkeeping (implicit string-length arithmetic, index
scaling, SUPER extent and descriptor calculations) stays under its INDEXCK,
RANGECK, allocation and descriptor contracts. It gets no MATHCK guard merely
because the compiler emits arithmetic instructions for it. This exclusion
neither weakens those contracts nor excuses LLVM undefined behavior in
generated calculations. Explicit user arithmetic that *supplies* a length,
index, position, count or extent is still MATHCK arithmetic at its own
operators.

*Implementation:* MATHCK+ scalar `+ - *` use LLVM's overflow intrinsics at
the adapted/promoted operand type and signedness, and fail through
`pas_math_overflow` (`runtime/mathck.c`) before the result is used. Signed
MIN DIV -1 is checked after the mandatory zero-divisor test, and unary minus
is a checked `0 - v`. Native compiler generations 2–4 are built with these
checks.

### MATHCK overflow definition

For an in-scope operation with MATHCK enabled, overflow means that the exact
mathematical result is outside the native range of the operation's resolved
result type, including its width and signedness. The range is never inferred
from the destination of a later assignment; store-time subrange checks remain
RANGECK. A signed N-bit type has the range `-2^(N-1)..2^(N-1)-1` and an
unsigned one `0..2^N-1`, for N = 8, 16, 32 and 64. This is a mathematical
definition, not a requirement to compute the exact result in a same-width
machine integer before checking it.

- **The INTEGER minimum is ordinary data.** Native INTEGER is
  `-32768..32767`, with no reserved `#8000` result, sentinel exception or
  separate MATHCK range. `-32767 - 1`, `-16384 * 2` and `PRED(-32767)` give a
  valid `-32768`; `32767 + 1`, `-(-32768)`, `ABS(-32768)`, `SQR(200)` and
  `-32768 DIV -1` overflow. The same endpoint rules apply at every signed
  width.
- **Unsigned arithmetic.** WORD is `0..65535`. Subtraction below zero
  (`0 - 1`) and addition or multiplication above the maximum overflow.
- **WORD unary minus** succeeds for zero; negating any nonzero WORD-family
  value overflows. There is no compile-time warning merely for unary minus on
  WORD, but ordinary constant-range errors still apply.
- **DIV and MOD.** Division truncates toward zero, and the remainder has the
  dividend's sign; WORD-family DIV/MOD are unsigned. A zero divisor is a
  division-by-zero error, not a representability test. Signed `MIN DIV -1`
  overflows. `MIN MOD -1` is the representable zero and succeeds: MOD does not
  inherit a trap because a machine quotient would overflow. Neither operation
  executes LLVM undefined behavior to obtain its result.
- **Builtins.** SUCC of the base-type maximum and PRED of its minimum
  overflow. Signed ABS overflows only for MIN, WORD-family ABS returns its
  argument, and SQR overflows when `v * v` is not representable.

A representable result never overflows merely because it equals a historical
IBM invalid value.

### Disabled MATHCK semantics

MATHCK- disables representability traps. It does not license LLVM undefined
behavior or optimization-dependent results, and the same resolved result width
and signedness apply as with checking enabled.

- `+ - *`, unary minus, SUCC/PRED, ABS and SQR wrap: the result keeps the low
  N bits of the exact result (modulo `2^N`), interpreted as unsigned for
  WORD-family types and as two's-complement for INTEGER-family types. So
  `32767 + 1` is `-32768`, `ABS(-32768)` stays `-32768`, and WORD unary minus
  of `1` is `65535`.
- DIV and MOD by zero still fail deterministically with the runtime
  division-by-zero diagnostic, never a machine exception or a fabricated
  result.
- Signed `MIN DIV -1` returns MIN. `MIN MOD -1` returns zero under either
  setting. Other DIV/MOD truncate as above.

None of this depends on the optimization level. MATHCK- does not relax
compile-time constant range and type errors (including constant zero
divisors), store-time RANGECK checks, conversion errors, or FOR termination.
Integer VECTOR code under MATHCK- keeps its single SIMD instruction; under
MATHCK+ each operation adds one whole-vector overflow test, so put
`{$MATHCK-}` around hot vector loops if the cost matters.

*Implementation:* native lowering guards dynamic zero divisors, sanitizes
signed MIN/-1 so no overflowing signed divide or remainder instruction
executes, and selects unsigned division for WORD-family operands at every
width. Even constant-dead division instructions get safe divisors.

### MATHCK constant operations

Every integer `+ - * DIV MOD` or negation whose value is fully determined at
compile time is folded exactly by the typechecker and must fit its own type,
independently of MATHCK. That type is the integer context's when there is one
(as for a literal, so `i32 := Base + Step` is 33000 with INTEGER CONSTs), and
otherwise the operands' result type. The rule applies at every node, so
`(M + 1) - 1`, `WRITELN(32767 + 1)`, `WRITELN(-N)` with `N = -32768`, and the
operand `M + 1` in `k := i + (M + 1)` are compile-time `integer constant out of
range` errors, not silent wrapping or a guaranteed runtime trap. A fully
constant SUCC/PRED/ABS/SQR call must fit its type the same way. A constant
zero divisor is rejected at compile time even with a dynamic dividend; the
[constant DIV/MOD rules](#constant-divmod-and-consumer-invariants) cover
truncating folds and their consumers. A partially constant operation is
checked at run time like any other.

*Implementation:* a valid constant operation is tagged with `resolved_type`,
and codegen materializes that exact value at that type instead of evaluating
its operands again at literal width (`j := i + (M + 1)` with INTEGER32 `j` is
32773). Legacy typed ASTs carry the old reference's BinOp `resolved_type`,
which codegen uses the same way; an untagged constant operation stays
unchecked.

### MATHCK directive snapshots

Each in-scope operation uses the effective MATHCK setting at its own source
token, not at the end of its expression, at an assignment destination, or at
a routine declaration or call elsewhere:

- binary arithmetic uses its `+`, `-`, `*`, `DIV` or `MOD` token;
- unary minus uses its `-` token;
- `SUCC`, `PRED`, `ABS`, `SQR`, `VSUM` and `VPROD` use the function-name
  token, not a parenthesis or argument token.

The setting is captured before the parser advances past the token, so a
directive in the right operand or argument list affects only later tokens.
Each nested operation has its own snapshot: a builtin's setting does not
replace the settings of arithmetic in its arguments, and an ordinary call
does not impose the caller's setting on operations in the callee. With MATHCK
initially enabled:

```pascal
x := a + {$MATHCK-} b;             { + remains checked }
x := a {$MATHCK+} + b;             { this + is checked }
x := ABS({$MATHCK-} a + b);        { ABS checked; argument + unchecked }
{$MATHCK-} i := k + 1 {$MATHCK+};  { exactly this + is unchecked }
```

The existing directive machinery decides the setting: the enabled default,
`$DEBUG` coupling and later explicit overrides, PUSH/POP, numeric forms,
conditional compilation and includes. Include-file tokens carry their own
effective lexical setting, and only the active token stream of conditional
compilation counts; settings are never reconstructed from skipped text. The
snapshot is per operation, not a runtime flag, and survives parsing and
typechecking unchanged.

*Implementation:* the parser (`AddMathckSnapshot`/`AddOpLocation`,
`src/ps_expr.pas`) adds `mathck` (BOOLEAN) and `op_location`
(`{line, column}`) to BinOp `PLUS`/`MINUS`/`MUL`/`DIV`/`MOD`, to the
sign-minus UnaryOp, and to FuncCall nodes of the six builtins above. The
snapshot is syntactic (set, REAL and CHAR uses carry it too); later stages
decide applicability. The typechecker annotates nodes in place and never
rebuilds them. Codegen reads the metadata only from the operation's own node:
checked arithmetic and scoped builtins consume `mathck` and `op_location`,
and mandatory DIV/MOD zero checks consume `op_location` regardless of
`mathck`. Never read `mathck` from another node or a flags object: cJSON key
lookup ignores case, so a flags object's `MATHCK` entry would match.

### MATHCK legacy AST compatibility

A BinOp, UnaryOp or scoped builtin FuncCall without a MATHCK snapshot is a
legacy unchecked operation. Absence does not mean the current source default,
an enclosing node's setting, or a request to reconstruct directive state, and
no enabled snapshot is synthesized merely because MATHCK defaults to enabled.
The rule is per node: an unchecked parent does not erase an explicit snapshot
on a nested operation.

Legacy unchecked operations follow the [disabled semantics](#disabled-mathck-semantics):
wrapping, deterministic zero-divisor errors (reported at `line 0 column 0`,
since the node has no coordinates) and defined signed MIN/-1 results.
Unchecked never means unsafe LLVM lowering. The frozen AST files in
`tests/corpus/reference/` stay unchanged and keep their valid-program outputs; new
snapshot metadata does not justify rewriting them to opt into checking.
Compatibility does not preserve values that came from LLVM undefined behavior
(UB: an operation such as integer division by zero or overflowing signed
MIN/-1 division, for which LLVM gives no valid-result guarantee and
optimization can produce arbitrary results or crashes), crashes or
optimization-level differences. Such observations are not a language
contract.

*Implementation:* `SiteMathCk` in `src/cg_expr.pas` applies the
absent-snapshot policy.

### MATHCK and RANGECK

MATHCK checks the representability of an in-scope operation in its resolved
base result type. RANGECK keeps domain and destination constraints; a
narrower destination does not redefine the operation's overflow range.

- Store-time subrange checks (`EmitSubrangeCheck`) are RANGECK checks.
- SUCC/PRED bounds for CHAR, BOOLEAN, enumeration and subrange domains belong
  to RANGECK; INTEGER/WORD-family base-type endpoint overflow belongs to
  MATHCK. For a numeric subrange both are distinct checks. Enumeration domain
  checking does not bring enumeration arithmetic into MATHCK's scope.
- Each switch controls only its own checks. MATHCK- does not disable RANGECK,
  and RANGECK- disables neither MATHCK nor mandatory zero-divisor errors.
  Disabled base arithmetic follows the wrapping/division rules rather than
  borrowing protection from RANGECK.

When both apply to the same result, base-type overflow is checked first and
the domain or store range second. A MATHCK failure terminates before a
RANGECK check can consume the failed result; if the arithmetic succeeds but
violates an enabled domain or destination check, RANGECK reports it. Neither
failure publishes the failed result to a destination or lets later user code
use it. This ordering concerns checks on one result, not operand evaluation
order or unrelated checks. For example, INTEGER `32767 + 1` overflows under
MATHCK+ before any store check; an addition yielding `11` is representable,
but storing it in `0..10` fails under RANGECK+; SUCC of `10` in that subrange
is a domain failure, not INTEGER overflow; and at an endpoint shared by a
numeric subrange and its base type, the enabled base overflow check wins.

Under RANGECK+ (the statement's setting, as for store checks), stepping a
CHAR, BOOLEAN or enumeration value past its first or last ordinal fails before
the step. A result outside the declared bounds of a subrange argument whose
type is evident at the call (a variable, designator or nested SUCC/PRED)
fails after it. Both use the existing `runtime error: value V is outside
subrange LO..HI` text. A subrange value that reaches SUCC/PRED any other way
(for example, a function result) is stepped in its host type and checked
where it is stored.

### MATHCK runtime diagnostics

Under MATHCK+, the first failing operation reports one line on stderr:

```text
runtime error: MATHCK <class> in <operator> at line L column C (<operands>)
```

```text
runtime error: MATHCK signed overflow in + at line 12 column 10 (left=32767, right=1)
runtime error: MATHCK unsigned overflow in * at line 7 column 12 (left=65535, right=2)
runtime error: MATHCK signed overflow in SUCC at line 9 column 8 (operand=32767)
runtime error: MATHCK signed overflow in VSUM at line 4 column 8 (left=20000, right=20000)
runtime error: MATHCK signed division by zero in DIV at line 5 column 13 (left=7, right=0)
```

- The class is `signed overflow`, `unsigned overflow`, `signed division by
  zero` or `unsigned division by zero`, from the resolved arithmetic type.
- The operator is the source spelling (`+ - * DIV MOD`; unary minus is `-`)
  or the uppercase builtin name (`SUCC`, `PRED`, `ABS`, `SQR`, `VSUM`,
  `VPROD`).
- The coordinates are the operator or function-name token used for the
  snapshot, not the destination or the end of the expression.
- Binary operators append `(left=L, right=R)`; VSUM/VPROD append the partial
  result and the lane in the same form; unary minus and the scalar builtins
  append `(operand=X)`. Operands are the original values already computed,
  formatted by their signedness and width, never a wrapped result or a
  fabricated quotient, and are never evaluated again. Reporting them has no
  side effects and exposes no LLVM undefined behavior. A failing VECTOR lane
  reports its own operands, the lowest failing lane first.

Failure handling, under MATHCK+ and for mandatory zero-divisor errors under
MATHCK-, follows the `runtime/subrange.c` and `runtime/array_index.c`
convention: flush stdout so prior output survives, print the single line to
stderr and flush it, then call `abort()` before the failed result can be
stored or used. Tests require failure and the exact line, not a
platform-specific signal number or exit status. There is no second error line
and no IBM error number in the message. For historical reference only, the
classes correspond to IBM Appendix A errors 2051 (Unsigned Divide By Zero),
2052 (Signed Divide By Zero), 2053 (Unsigned Math Overflow) and 2054 (Signed
Math Overflow); this mapping does not adopt IBM's INTEGER sentinel or range
rules. Compile-time constant errors and unsupported-boundary diagnostics are
separate from this runtime format.

CHR takes `$RANGECK` and diagnostic coordinates from the function-name token,
not a directive inside its argument. Its argument is evaluated once. On a host
failure, `pas_chr_error` prints
`runtime error: RANGECK CHR argument V is outside 0..255 at line L column C`,
flushes stdout/stderr and aborts before publishing the character. This separate
entry preserves the subrange-error ABI. Constant consumers such as CONST
reject an enabled out-of-domain CHR while codegen folds it; ordinary constant
calls use the same runtime guard as variable calls. Legacy calls lacking the
snapshot inherit scoped RANGECK and report coordinates 0/0. CPU DEVICE shares
the host failure path; NVPTX retains its existing unchecked RANGECK conversion.
User routines named CHR are not the builtin. `tests/contract/rangeck_chr.sh`
checks these boundaries at O0–O3. This does not implement BYWORD checking.

Constant CHR values use the same low-eight-bit representation as runtime CHR:
under RANGECK-, `ORD(CHR(300)) + 1` is 45, not 301, and
`ORD(CHR(-1)) + 1` is 256, not 0. Both native constant folders normalize the
converted ordinal, including negative and MIN64 arguments, without negating
their magnitude; the backend checks the original domain before normalizing.
This applies to CONST
transport, admitted CASE labels and array-bound consumers as well as arithmetic;
it does not erase an enabled bad-argument check or broaden constant syntax.
`tests/contract/chr_constant_folding.sh` pins constant/runtime twins in both
dialects at O0–O3 and the CONST/label/bound consumers.

The other checks keep their own texts and never use the MATHCK stem: RANGECK
prints `value V is outside subrange LO..HI`, INDEXCK `array index V is outside
bounds LO..HI at line L column C`, INITCK `INITCK uninitialized ...`, and TRUNC/ROUND their
[conversion error](#trunc-and-round-return-integer-so-they-narrow-to-16-bits-both).
Existing subrange RANGECK messages stay unlocated, and SUCC/PRED domain failures say
"subrange" even for CHAR, BOOLEAN and enumeration domains. Adding coordinates
or domain-specific wording would change the `pas_subrange_error` runtime
interface and every store-check caller; that is RANGECK's own diagnostics
work (located classes, file/include identity, runtime ABI compatibility), not
a MATHCK change.

*Implementation:* `pas_math_zero` and `pas_math_overflow` in
`runtime/mathck.c`.

### MATHCK builtin classification

Every builtin that does integer arithmetic on, or converts, a user value
belongs to exactly one of the groups below. A user routine of the same name
is an ordinary call, outside this classification.

| Group | Builtins | Rule |
|---|---|---|
| MATHCK | `SUCC`, `PRED` (integer family) | Checked `v ± 1` at the argument's width (`overflow in SUCC`/`PRED`). |
| MATHCK | `ABS` | Signed: checked `0 - v` for negative `v`; only MIN overflows. WORD family: returns its argument, no arithmetic. |
| MATHCK | `SQR` (integer family) | Checked `v * v`. |
| MATHCK | `VSUM`, `VPROD` (integer lanes) | Checked left-to-right fold of `+`/`*`. `VMIN`/`VMAX` cannot overflow. |
| Never trapping | `SADDOK`, `SMULOK`, `UADDOK`, `UMULOK` | Return the 16-bit "fits" flag and store the wrapped result (IBM 11-21); described below. |
| RANGECK | `SUCC`, `PRED` on CHAR, BOOLEAN, enumerations, subranges | Domain checks under RANGECK+ ([above](#mathck-and-rangeck)). |
| RANGECK | `CHR` | IBM: "error if ORD (X) > 255 or ORD (X) < 0 (if $RANGECK on)" (11-8). Checked before truncating the original signed/unsigned integer to CHAR; disabled checking retains the low eight bits. |
| Separate contract | `TRUNC`, `ROUND` | Always-on range check, independent of MATHCK and RANGECK (G26, [TRUNC section](#trunc-and-round-return-integer-so-they-narrow-to-16-bits-both)). |
| RANGECK | `CONCAT` (LSTRING length byte) | Host RANGECK+ checks combined length against `min(capacity, 255)` before copying or publishing; failure leaves compiler-written destination bytes unchanged. RANGECK- and NVPTX remain unchecked; this is not MATHCK arithmetic. |
| Separate contract | `INSERT`, `DELETE`, `COPYLST`, `COPYSTR`, `POSITN`, `ENCODE`, `DECODE` | **Unreachable:** codegen lowers them, but the typechecker rejects every call as an undefined procedure or function. When enabled, their internal length and position arithmetic (`pos - 1`, `len - pos`) needs capacity and position checks, not MATHCK; DECODE is a text-to-number conversion. |
| Separate contract | `NEW` bounds, `DEVALLOC`, `SIZEOF`, `LOWER`, `UPPER` | Descriptor and layout arithmetic; layouts above 2147483647 bytes are rejected (`TypeSizeBytes`). |
| Separate contract | `READ`/`READLN` of integers | Text conversion, checked independently of MATHCK (G29). |
| No check | `ORD` | Same value and width; an enumeration gives its ordinal as INTEGER, so `ORD(e) * 20000` is checked 16-bit arithmetic. [`ORD(WORD)`](#deferred-ordword-conversion-gap-g25) stays WORD (G25). |
| No check | `WRD`, `WRD8` | Bit-pattern conversion: `WRD(-2)` is 65534 (IBM 11-8). |
| No check | `ODD` | Low-bit test. |
| No check | `HIBYTE`, `LOBYTE` | Byte extraction, never above 255. They return CHAR; IBM returns the argument's type, a typing difference, not a MATHCK question. |
| No check | `BYWORD` | Packs the low byte of each operand: `BYWORD(300, -1)` is 11519. IBM requires one-byte operands; masking wider ones is a typing difference, not overflow. |
| No check | `FLOAT` | Exact for every INTEGER-family value up to 2^53; WORD-family values convert unsigned ([WORD to REAL](#word-to-real-conversion)). |
| No check | `RETYPE`, `ADR`, `ADS`, pointer `+` | Reinterpretation and [address arithmetic](#outside-mathck). |

`FILLC`, `FILLSC`, `MOVEL`, `MOVER`, `MOVESL` and `MOVESR` are not builtins:
the typechecker reports `Undefined procedure`, and the runtime library
defines them under lower-case C names. Their counts are memory-region bounds,
not MATHCK.

The IBM library functions `SADDOK`, `SMULOK` (A, B: INTEGER; VAR C: INTEGER)
and `UADDOK`, `UMULOK` (A, B: WORD; VAR C: WORD) return TRUE when the 16-bit
sum or product fits and always store the wrapped result in C; they never
trap, under either MATHCK setting. The manual has programs declare them
`EXTERN`. Here they are also available undeclared, lowered inline, and the
runtime library defines them for an `EXTERN` declaration spelled in capitals
as in the manual (EXTERN names keep their source case, so another spelling
does not link). Any user declaration of the name takes precedence. There are
no wide variants: extended mode has the same 16-bit functions. Under INITCK+,
like the other builtins outside INITCK's model, a call stops at the
`call consumer` boundary.

### SCANEQ and SCANNE **[both]**

`SCANEQ(L, P, S, I)` and `SCANNE(L, P, S, I)` are host builtins returning
INTEGER. Count `L` and 1-based position `I` must fit INTEGER; `P` is CHAR,
and `S` is STRING or LSTRING. SCANEQ stops at equality, SCANNE at inequality.
They return the signed count of skipped characters; negative `L` scans
backward. With no stopping character they return `L`, even when a string
boundary is reached first, without reading outside the string. A zero count,
empty string or starting position outside `1..length(S)` returns zero.
Arguments evaluate once, left to right. User declarations shadow the builtins.

Literal, variable, selected-string and native string-function sources are
supported. DEVICE calls are rejected: these are host runtime functions.
INITCK-enabled calls retain the explicit `call consumer` unsupported boundary;
string initialization tracking is not implemented. These scans neither write
the string nor add MATHCK instrumentation. Tests: `tests/corpus/golden/scan_builtins.pas`
and `scan_shadow.pas`, `tests/corpus/checklit/scan/`, and
`tests/unit/runtime_scan.c`.

### MATHCK VECTOR, DEVICE and unsupported boundaries

**VECTOR [extended].** Under the operation's MATHCK+ snapshot, integer lane
`+ - *` and unary minus are checked per lane. Lane DIV/MOD use the scalar safe
division under either setting: a zero lane fails with the zero-divisor
diagnostic, and signed MIN/-1 gives MIN (DIV, MATHCK-), an overflow (DIV,
MATHCK+) or 0 (MOD). No vector division instruction is emitted. Integer
VSUM/VPROD are left-to-right folds of checked steps under MATHCK+. MATHCK-
lane `+ - *`, negation and reductions keep the wrapping SIMD instructions.
REAL lanes are unchanged. VECTOR is rejected on NVPTX altogether, so only host
and CPU DEVICE code reaches these paths. *Implementation:* one vector overflow
intrinsic computes every lane and the code branches once on the OR of the
overflow lanes; only on failure does a cold path redo the operation lane by
lane, in lane order, through the scalar checked paths (`CodegenLanewiseIntOp`,
`CodegenLanesIntOp` and `CodegenCheckedVReduce` in `src/cg_expr.pas`).

**DEVICE.** NVPTX code has no host failure path, and no device-side error
channel (state in device memory, transport across LAUNCH, a non-trapping way
to stop the failing thread) is planned. An operation that its MATHCK+
snapshot would check there (`+ - * DIV MOD`, unary minus, SUCC/PRED, signed
ABS, SQR; not a fully constant fold and not WORD ABS) is therefore rejected as
a `DEVICE arithmetic` boundary. MATHCK- at the operation is the opt-out and
wraps. DIV/MOD stay rejected on NVPTX under MATHCK- as well, because the
mandatory zero-divisor failure has no device path either. Because MATHCK
defaults on, NVPTX kernels with integer arithmetic need `{$MATHCK-}` (see
[GPU (NVPTX) kernels](#gpu-nvptx-kernels-need-mathck--for-integer-arithmetic-extended)).
Unlike INITCK, which keys its boundary on every DEVICE compiland, MATHCK keys
it on NVPTX only: CPU DEVICE code links the host runtime, so its kernels are
checked through LAUNCH exactly like host code. The SUCC/PRED RANGECK domain
checks remain skipped on NVPTX (RANGECK's own open DEVICE decision).

**Unsupported-boundary policy.** An enabled in-scope operation whose checks
are not implemented is a hard compile-time error, never a warning or silent
unchecked acceptance, reported at the operator or function-name token before
any IR is published:

```text
MATHCK unsupported boundary: <category> at line L column C
```

| Category | Unsupported enabled operation |
|---|---|
| `scalar arithmetic` | ordinary INTEGER/WORD scalar operation lacking its checks |
| `wide arithmetic` | extended-width scalar operation lacking its checks |
| `VECTOR arithmetic` | in-scope integer VECTOR operation lacking its checks |
| `DEVICE arithmetic` | in-scope integer operation in DEVICE code lacking its checks |

Only `DEVICE arithmetic` on NVPTX can occur today; scalar, wide and host/CPU
VECTOR checks are implemented. A category stops being a boundary for an
operation once its checks exist; the policy is not a permanent ban. Merely
enabling MATHCK is silent when no unsupported operation is encountered, and
declarations or out-of-scope operations never trigger the diagnostic. MATHCK-
at the operation, or a legacy node without a snapshot, opts out of checking
but not out of safety: wrapping, zero-divisor failure and safe MIN/-1
handling still apply where the operation is admitted, and other type, target,
range and descriptor constraints are unchanged. *Implementation:*
`MathckDeviceBoundary` in `src/cg_expr.pas`.

### Outside MATHCK

- **REAL arithmetic (G27).** REAL and REAL32 `+ - * /`, unary minus, and REAL
  ABS/SQR/SQRT/LN/EXP follow IEEE 754 under either setting: overflow gives
  `INF`/`-INF`, `x / 0.0` a signed infinity, and `0.0 / 0.0` or `INF - INF` a
  NaN (printed `-NAN` on x86-64, following the platform). Nothing traps, and
  MATHCK neither adds nor removes a REAL check. IBM's always-on REAL function
  checks (11-8, through its real-math library) are not reproduced. Any future
  REAL checking needs its own directive decision, not MATHCK.
- **Conversions.** TRUNC/ROUND have their own always-on range check
  ([TRUNC section](#trunc-and-round-return-integer-so-they-narrow-to-16-bits-both)).
  `ORD`, `WRD`, `CHR` and the other conversions are not MATHCK operations
  ([builtin classification](#mathck-builtin-classification)).
- **Address arithmetic.** Pointer or ADRMEM `+` an integer offset (either
  order) lowers to a non-inbounds GEP scaled by the pointee size (bytes for
  ADRMEM). It wraps in the address space without LLVM undefined behavior and
  never traps, under either setting. The offset widens to 64 bits by its own
  signedness (a literal by its exact value), so a WORD offset of 40000
  addresses element 40000. Arithmetic *inside* the offset (`p + (n - 1)`) is
  ordinary MATHCK arithmetic. `p - n`, `p * n`, `p DIV n` and a REAL offset are
  typecheck errors (`Pointer arithmetic supports only pointer + integer
  offset`). Pointer validity belongs to the NILCK, INDEXCK and descriptor
  contracts.
- **`[C]` and other EXTERN code.** Arithmetic inside the routine is invisible
  to the compiler. A returned CINT/CLONG/CSIZE_T or other integer value is
  ordinary data in Pascal, checked at its own type (CINT `+` is INTEGER32
  arithmetic).
- **Compiler bookkeeping** and **FOR stepping**, as described under
  [operation scope](#mathck-operation-scope).

### Explicit MATHCK differences from IBM Pascal 1981

These are deliberate native decisions.

- **No `#8000` exclusion or sentinel range.** IBM excludes the exact
  `-MAXINT-1` result from checking and describes signed overflow against
  `-MAXINT..MAXINT`. Native INTEGER is the full `-32768..32767` range;
  representable `-32768` results are ordinary data, and only exact results
  outside the real result-type range overflow.
- **Defined disabled arithmetic.** Rather than reproducing IBM's undefined
  disabled ABS/SQR results or incidental overflow traps, native MATHCK-
  `+ - *`, unary minus, SUCC/PRED, ABS/SQR wrap at the result width. DIV/MOD
  by zero always fail deterministically; signed `MIN DIV -1` returns MIN,
  and `MIN MOD -1` returns zero. IBM's statement that disabling MATHCK does
  not always disable checking permits the retained zero-divisor errors but
  does not specify these wrapping results.
- **Extended widths and VECTOR.** IBM's INTEGER/WORD arithmetic contract is
  16-bit. Native extended-width scalar types and integer VECTOR lanes use the
  same exact-result and disabled-behavior rules at their own widths. This is
  an extension, not an IBM compatibility claim.
- **Mixed INTEGER/WORD operands rejected.** IBM requires both operands of
  `+ - * DIV MOD` to be INTEGER or both WORD; native enforces that with a
  compile-time error (constants adapt where they fit) rather than guessing an
  interpretation.
- **WORD negation warning omitted.** IBM always warns for unary minus on
  WORD. Native emits no unconditional warning: zero succeeds, nonzero
  negation overflows under MATHCK+, and MATHCK- negation wraps.
- **No 8088 flag/pathology emulation.** Overflow uses exact representability,
  not historical machine flags or optimization-dependent trap behavior.
  Signed `MIN MOD -1` succeeds with zero, without inheriting a quotient trap.
- **Native diagnostic presentation.** Errors identify the class, source
  operator, operands and token coordinates rather than printing IBM numbers
  2051–2054. Those numbers are historical mappings only.
- **GPU kernels.** IBM had no GPU target. NVPTX kernels must use `{$MATHCK-}`
  for checked integer operations, which are otherwise compile-time errors.

REAL arithmetic and TRUNC/ROUND conversion errors remain outside MATHCK;
that separation is retained from IBM, not a new difference (IBM's always-on
REAL function checks are not reproduced; TRUNC/ROUND's range check is).

## Integer widths

`INTEGER` and `WORD` are **[both]**. Every wide type in this table is
**[extended]**; a vintage program must not use it.

| Type | Width | Notes |
|---|---|---|
| `INTEGER` | **16-bit signed** | the default; native range is `-32768..32767` |
| `WORD` | 16-bit unsigned | `0..65535` |
| `INTEGER32` | 32-bit signed | extended only; what you want for a length or an offset |
| `INTEGER64` | 64-bit signed | extended only |
| `WORD8`/`WORD32`/`WORD64` | unsigned | extended only |
| `CINT` | 32-bit signed | C `int`, for `[C]; EXTERN;` declarations |
| `CLONG` | 64-bit signed | C `long` |
| `CSIZE_T` | 64-bit unsigned | C `size_t` |
| `REAL` | 64-bit float | `REAL32` is the 32-bit one, extended only |

`INTEGER`'s range is the full two's-complement `-32768..32767` in both
dialects, and `-32768` is an ordinary writable literal (a deliberate
difference from IBM, which reserved it; see the next section).

### WORD arithmetic and comparison boundaries

Scalar WORD-family DIV/MOD use unsigned `udiv`/`urem`, and ordering uses
unsigned predicates, at 8/16/32/64 bits after literal adaptation and width
promotion (`CodegenBinOp`, `src/cg_expr.pas`). INTEGER-family operations remain
signed; EQ/NE are signedness-neutral and wrapping add/sub/mul is unchanged.
G14–G17 and G21 are native correct-output requirements, independent of MATHCK;
Python compiler parity is not an acceptance criterion. Mixed-family arithmetic
admission is governed by [integer constants and context](#integer-constants-and-context),
not by unsigned instruction selection. DIV/MOD zero guards and signed MIN/-1
sanitization are implemented separately; unsigned lowering alone is not safety.

Comparison sites have distinct contracts; do not replace every signed predicate
with an unsigned one merely because WORD data can reach it:

| Site | Predicate/domain invariant |
| --- | --- |
| Scalar ordering | WORD uses unsigned predicates at the adapted/promoted width; INTEGER controls stay signed. A signed/unsigned pair compares exact values (negative below all unsigned), not one shared predicate. |
| CASE | Labels are coerced to selector type and compared with `icmp eq`; high-bit/max labels work at each width. CASE label ranges remain unsupported. |
| Set membership | Admitted ordinals normalize to i16, then sign-extend to i64; unsigned `< 256` excludes negative/high-bit patterns before safe bit lookup. WORD in an INTEGER set is a type error; even a matching WORD set reaches codegen rejection. These are admission limits, not WORD membership support. |
| Set constructors/ranges | Unsigned i16 `> 255` guards elements. Signed range comparisons operate on admitted INTEGER/CHAR/BOOLEAN/enum bounds, not WORD; equality/subset checks compare bitvectors. |
| Fixed/SUPER indices, subranges, VECTOR descriptor bounds | Unsigned sources zero-extend into wider signed i128, where signed bounds comparisons are correct even for WORD64. Blind unsigned conversion would break negative lower bounds. |
| VECTOR lanes | WORD DIV/MOD and ordering are unsigned; division guards/MATHCK scope are separate contracts. |
| FOR | WORD controls use unsigned ordering and loops exit at the final value, before an endpoint step could wrap. G18/G19 are correct-output requirements, independent of MATHCK; post-loop control value is undefined, not an oracle. |
| Other internal comparisons | String lengths/strcmp, signed counters/status, pointer/NIL and initialization equality are not WORD scalar ordering. WORD ABS is identity, including high-bit arguments; signed ABS overflow is a separate MATHCK operation. |

Under `$RANGECK+` (the setting at the CASE token), a selector with no matching
label and no `OTHERWISE` fails, including an empty CASE. The selector is evaluated
once. `$RANGECK-` retains fall-through; `OTHERWISE` handles a miss normally.
The separate `pas_case_error` runtime entry prints
`runtime error: RANGECK CASE selector V has no matching label at line L column C`,
flushes stdout/stderr and aborts before subsequent statements run. The value keeps
its original width and signedness; legacy ASTs without a statement location report
0/0. CPU DEVICE uses this host failure path; NVPTX retains its existing unchecked
RANGECK boundary, without a host runtime call. This does not alter the existing
subrange-error ABI or add file/include identity. `tests/contract/rangeck_case.sh`
checks misses, empty cases, selector-once behavior, OTHERWISE, scoped settings,
wide diagnostics and DEVICE target boundaries.

### WORD to REAL conversion

`IntToFloat` (`src/cg_types.pas`) selects `uitofp` for WORD-family operands
and `sitofp` for signed operands. Its callers include FLOAT/libm argument
conversion (`RealArgToDouble`), admitted mixed REAL/integer operands and `/`
promotion in `CodegenBinOp`, and `CoerceForAssign`. Thus `FLOAT(w)` for WORD
`w = 65535` is 65535.0, not -1.0; unsignedness must survive every conversion
site. Floating representation still rounds: WORD64 MAX converts to the double
18446744073709551616.0, not an exact integer value. These lowering rules do not
expand type admission or repair the separate ORD(WORD) gap.

The [WORD test map](testing/mathck.md#scalar-word-arithmetic-prerequisites)
records the nonzero-divisor runtime matrix and O0 unsigned/zero-extension IR
checks; the [FOR test map](testing/mathck.md#for-endpoint-termination) covers
endpoint termination separately. Compiler-source arithmetic dependencies and
fixed-point validation belong to the [bootstrap contract](bootstrap_subset.md#self-hosting-arithmetic),
not Python-reference parity or historical audit transcripts.

## Integer constants and context

Native decimal and radix constants from `-32768` through `32767` have type
`INTEGER`. Positive constants from `32768` through `65535` have type `WORD`.
Vintage mode rejects constants outside `-32768..65535`. Accepting `-32768`
is a deliberate modern divergence from IBM: compatibility is for fun, not
pathology, and INTEGER has no reserved INITCK sentinel. A minus sign applied
to the `WORD` constant `32768` folds to INTEGER `-32768`, so `-32768`,
`- 32768`, `-(32768)` and `-W` (with `CONST W = 32768`) all give `-32768`.
Negating a constant that is already `-32768` is a compile-time error, and so
is `0 - 32768`: a binary operation mixes a `WORD` constant with an `INTEGER`
operand only if the constant fits INTEGER.

An `INTEGER` constant can adapt to a `WORD` context. This includes negative
constants. The conversion keeps the 16-bit pattern, so `-1` becomes `65535`.
An `INTEGER` variable does not adapt in this way in assignment contexts.
For scalar `+ - * DIV MOD`, the decision is likewise to reject mixed
nonconstant INTEGER-family/WORD-family operands, in either order and at all
widths, regardless of MATHCK. Same-family width promotion and admissible
constant adaptation remain unchanged; explicit `WRD(i)` selects native WORD
interpretation. The typechecker rejects such a mixture with `Mixed
INTEGER-family and WORD-family operands need an explicit conversion (e.g.
WRD) in <op>`. An INTEGER-family constant still adapts to a WORD-family
operand (`w + (-1)` is unsigned WORD arithmetic), and a WORD-family constant
mixes with a signed operand only if it fits that operand's type (`a + 40000`
with INTEGER32 `a` is fine; `i + 40000` with INTEGER `i` is rejected). The
constant exception applies per operand at every width (negative INTEGER-family
constants adapt by bit pattern, as at 16 bits). A rejected expression has no
arithmetic result type or overflow class, and neither MATHCK- nor a
destination type admits the mixture. This follows IBM §6-5 (manual lines
6144–6147) and §8's same-family rules. The decision covers scoped scalar
arithmetic only; it adds no rules for comparisons, assignments, REAL, VECTOR
or pointer arithmetic. *Implementation:* the typechecker's BinOp check and
`ConstantAdaptsToOperand` (`src/tc_expr.pas`) reject the mixture before any IR
exists.

Operands of different widths in the same family widen to the wider operand,
which is the result type: `INTEGER32 * INTEGER` is INTEGER32 arithmetic,
checked (MATHCK+) or wrapped (MATHCK-) at 32 bits, so `100000 * 20000` is
2000000000. Comparisons are not covered by this rule. A relational between a
nonconstant INTEGER-family and WORD-family operand, at any pair of widths,
compares exact mathematical values: a negative signed operand is below every
unsigned value, even one with the same bit pattern (`-1 < 65535` and
`-1 <> 65535` are TRUE for INTEGER and WORD), and otherwise the values compare
unsigned at the wider width. IBM only warns about such a mixture and leaves
its signedness arbitrary (manual lines 6188–6190); exact comparison is a
deterministic choice within that latitude. A bare INTEGER literal still
adapts to the other operand's type first, as above (`CodegenBinOp` and
`CodegenMixedSignCompare`, `src/cg_expr.pas`;
`tests/corpus/golden/mixed_sign_compare.pas`).

Real division `/` produces `REAL` for any combination of integer-family
(`INTEGER`, `WORD`, extended wide types) or floating-point operands and
literals; integer operands are promoted to `REAL` before division
(`CodegenBinOp`, `src/cg_expr.pas`; `CheckExpr`, `src/tc_expr.pas`;
`tests/corpus/golden/slash_integer_family.pas`,
`tests/corpus/golden/slash_wide_integers.pas`). Assigning the result of `/` to an
integer variable is rejected as a type mismatch without narrowing
(`tests/corpus/golden/slash_assign_to_int_rejected.pas`), and so is assigning it to
a `REAL32` variable, the same as any other `REAL` value
(`tests/corpus/golden/slash_assign_to_real32_rejected.pas`).

In extended mode, a literal can use a wide target type. These examples are
valid:

```pascal
VAR n: INTEGER32; w: INTEGER64;
CONST BIG = 100000;
BEGIN
  n := 40000;          { 40000 }
  n := 16#9C40;        { 40000, radix notation }
  n := -70000;         { -70000 }
  n := BIG;            { 100000 }
  w := 5000000000;     { 5000000000 }
```

`tests/corpus/golden/19_wide_int_literals.pas` pins this behavior.

Outside an assignment context a literal has its own type: 32768..65535 is a
WORD constant (both dialects), and a larger extended literal is INTEGER32
up to MAXINT32, then WORD32 up to 4294967295, then INTEGER64, so
`WRITELN(40000)` prints 40000 and `i < 40000` with INTEGER `i = -1` is TRUE
(an exact mixed-sign comparison). A literal of plain INTEGER range still
adapts to the other operand of a binary operation. `tests/corpus/golden/literal_word_range.pas`
and `tests/corpus/golden/literal_wide_range.pas` pin this. Literals of more than 15 digits
(beyond the precision of a printed JSON double) are preserved exactly across compiler
stages via companion decimal representation (`tests/corpus/golden/literal_int64_exact.pas`).

A literal too large for its target type is an error:

```pascal
VAR s: INTEGER;
BEGIN
  s := 40000;
END
```

The compiler also rejects implicit narrowing, such as assigning an
`INTEGER32` variable to `INTEGER`. Use an explicit conversion when truncation
is intentional. Assignment, value-parameter, array-index, and `FOR`-bound
contexts apply the same constant range checks.

### Constant DIV/MOD and consumer invariants

Integer constant DIV truncates toward zero; MOD has the dividend's sign,
with `a MOD b = a - (a DIV b) * b`. Thus `-5 DIV 2 = -2` and
`-5 MOD 2 = -1`, not Python floor results. This rule is independent of MATHCK.
A constant zero divisor is rejected with `Constant division by zero`, even
with a dynamic dividend or a divisor expressed through names/nested arithmetic;
it must not merely make the expression unfoldable.

Both `FoldConstInt` implementations (`src/tc_expr.pas`, `src/cg_types.pas`)
and their consumers use the exact truncating value before target-width
materialization. For example `CONST N = -65537` in extended mode gives
`N DIV 2 = -32768`, a representable INTEGER and the legal lower edge of
`ARRAY [-32768..-32767]`. MIN MOD -1 is zero. Existing constant range/overflow
rejection remains: MIN DIV -1's exact positive result does not fit its signed
type merely because unchecked runtime division would wrap.

| Consumer | Enduring invariant |
| --- | --- |
| Typechecker `CheckExprForSetTarget` / unary literal typing | Exact folded values control range errors and assignment/argument adaptation; recursive arithmetic has no separate rounding rule. |
| Typechecker `CheckDesignator` | Constant bound checks agree with codegen's index rebuilding, including large negative indices. |
| `CheckDecl`, `CheckConstOrdinalBounds`, CASE/type/array-bound checking | Recorded CONST values and nested SUCC/PRED arguments retain the same fold and existing domain checks; there is no second floor folder. |
| Codegen `IsIntLiteralLike` / `IntLiteralValue`, `CoerceForAssign`, `CodegenBinOp` | General-expression and 8/32/64-bit or wider ordinal adaptation rebuild the exact value before promotion. Shadowed names must not replace variables/user routines with constants; mixed-width negative remainders obey the same rule. |
| `CodegenDesignator`, `CodegenVload` / `CodegenVstore` | VECTOR and fixed/SUPER index reconstruction, rebasing and bounds checks use the same folder and shadow filter; no local signed rounding adjustment. Existing scalar/vector bounds contracts still apply. |
| `SuperBoundBits` | Exact INTEGER constants survive before i16 materialization; dynamic/unsigned bounds retain extension and runtime descriptor validation. |
| `CodegenConstDecl` | CONST tables feed subsequent CASE labels/array bounds with the same exact values; independent typechecker/codegen zero-divisor rejection also applies to parser-derived AST inputs. |

These internal consumers do not broaden the source CONST/CASE/bound grammar:
its permitted constants/names/selected constructors are not general binary
arithmetic. Direct AST probes test otherwise unreachable folder routes, not
new source syntax. The Python reference compiler is not the numeric oracle.
Broader constant-width/overflow and JSON literal-precision limits remain
separate constraints; runtime checks, operator locations and VECTOR division
safety are separate contracts, not consequences of correct folding. Compiler
self-hosting requires no floor-rounding workaround; its
[arithmetic rules](bootstrap_subset.md#wide-limits-word-and-division) and clean
fixed-point gate are separate. The [focused test map](testing/mathck.md#constant-divmod-folding-prerequisite)
describes runtime twins, zero rejections and CONST/CASE/bound AST probes.

## `TRUNC` and `ROUND` return `INTEGER`, so they narrow to 16 bits **[both]**

This one is real in both dialects. Both produce a 16-bit
`INTEGER` result even when assigned to an `INTEGER32`. A result outside
`-32768..32767`, or a NaN argument, is a run-time error, as IBM specifies
("Error if ABS(X) > MAXINT", 11-6). The check is always on and is
independent of `$MATHCK` (and of `$RANGECK`):

```pascal
r := 100000.0;
n := TRUNC(r);     { runtime error: TRUNC result out of INTEGER range at line L column C (value=100000) }
n := ROUND(r);     { the same, naming ROUND }
```

`TRUNC` keeps arguments strictly between `-32769` and `32768`; `ROUND`
rounds halves away from zero first, so `ROUND(32767.5)` fails and
`ROUND(-32768.4)` is `-32768`. The location is the function name's. A
constant argument is checked at run time too. CPU `DEVICE` code fails the
same way. NVPTX `DEVICE` code has no host failure path, so there the
conversion saturates instead (`TRUNC(1.0E10)` is `32767`, NaN gives `0`);
this is defined, but it is not IBM's error, and it is recorded as a device
gap. *Implementation:* `CodegenCheckedRealToInt` (`src/cg_expr.pas`) guards
`fptosi` with ordered compares, which also reject NaN, so no out-of-range
conversion reaches LLVM poison; failures go through `pas_conversion_error`
(`runtime/numeric.c`) at the parser's `op_location`, with no MATHCK
snapshot. NVPTX uses `llvm.fptosi.sat`.

Do not use `TRUNC` to read a number out of JSON, a file, or anything else that
can exceed 32767. The runtime provides `pas_cjson_int32`, `pas_cjson_int64`
and `pas_double_to_int64` for exactly this, and `jsonx`'s `JxIntValue`,
`jsonutil`'s `GetInt` and the compiler's own constant folder all go through
them.

`ORD` does not have this problem: `ORD` of an `INTEGER32` keeps its width.

### Deferred `ORD(WORD)` conversion gap (G25)

Currently ORD of any integer-family argument preserves its type, width,
signedness and value. In particular, `ORD(w)` for native WORD remains WORD;
assignment to INTEGER is rejected as implicit narrowing. IBM instead returns
INTEGER with the same 16-bit pattern (`32768` becomes valid `-32768`, `65535`
becomes `-1`; IBM §11-6/7, manual lines 11896–11908). The compatibility fix
is explicitly **deferred**; it does not block MATHCK. Current ORD of WORD is
therefore not a back door around the
[mixed-operand rule](#integer-constants-and-context), and the current behavior
is a recorded compatibility gap, not a ratification of IBM parity. G25 remains
a known-gap rejection in the [baseline](testing/mathck.md#mathck-gap-baseline).

ORD is a conversion, not a MATHCK operation: changing MATHCK must not change
its semantics, and because native `-32768` is valid data, a future
same-pattern conversion must not trap merely for producing it. A separate
conversion change must decide the extended WORD-family result types, update
the typechecker and codegen together, audit bootstrap/pasboot dependencies,
and test low/high-bit boundaries plus subsequent arithmetic and assignment.

## Differences from the Python compiler

The native compiler and the Python compiler differ for two vintage `WORD`
constant cases. The Python compiler rejects untyped positive constants from
`32768` through `65535`. The native compiler accepts these constants as
`WORD`, as specified in the August 1981 manual.

The Python compiler also rejects negative `INTEGER` constants in a `WORD`
context. The native compiler keeps the 16-bit pattern. For example, it converts
`-1` to `65535` in that context.

The Python command line supports individual `-f` feature overrides. The native
command line supports only the `vintage` and `extended` feature sets.

## Small string native calls **[native]**

Small `STRING` and `LSTRING` values use the native SysV aggregate call ABI,
including when nested in records. Their leaves are contiguous CHAR bytes;
the LSTRING length byte is included. Arguments and function results preserve
the whole value, including when argument registers are exhausted. Larger
strings retain the existing MEMORY-class transport. Regression:
`tests/corpus/golden/small_string_abi.pas`.

## Native limitations **[native]**

These are implementation limitations, not vintage-language restrictions.

- **Compile-time diagnostic positions [both].** Typechecker errors end with
  ` at line L column C`, the same suffix codegen's located errors use. The
  position is the innermost node that carries one: an operator, a read, a
  designator, a statement's first token, or a declaration's name. It is a
  line and column only, with no file name, so an error inside an included
  file is ambiguous. Typed ASTs from older parsers without `location` fields
  get positions only where `read_location`/`op_location` exist.

- **Very large unsigned literals [extended].** The JSON AST stores numbers as
  `REAL`, so decimal `WORD64` literals above `2^53` cannot preserve every bit.
  Use `MAXWORD64` for the upper boundary.
- **Array allocation size [both].** Vintage `WORD` bounds through `65535` are
  retained. A large valid range can still request a correspondingly large
  object from LLVM and the linker.
- **At most about 500 names in scope at once [both].** Codegen keeps one
  symbol table of `MAX_SYMBOLS = 500` entries (`src/cg_base.inc`); a few are
  used internally, so a program can declare 498 global variables but not 499,
  which fails with `codegen: too many symbols` and no source location. A
  routine's locals are released when the routine ends, so the limit is on the
  names visible at one point (globals plus the enclosing routines' locals),
  not on a program's total. Generated test programs should reuse a few
  variables rather than declaring one per case.

## Other things that cost time **[both, unless marked otherwise]**

None of these are width-related, but all have produced a baffling error at
least once:

- **A single-character quoted literal is a `CHAR`, not a string.** `JxGet(node,
  'x')` fails to typecheck with "Argument type mismatch" against an `LSTRING`
  parameter while `JxGet(node, 'xy')` is fine. The error says nothing about the
  literal.
- **Quoted literal spellings are limited to 255 bytes**, including both
  delimiters and doubled embedded quotes. Unescaped payloads therefore max
  out at 253 characters. Oversized tokens are rejected with `Lexer Error:
  quoted literal exceeds 255-byte token limit`, not silently truncated;
  unterminated literals are rejected too. Build longer LSTRING values from
  shorter pieces. Regression: `tests/contract/quoted_literal_limits.sh`.
- **Comments do not nest.** A `{ }` comment containing a brace — including in
  prose, or in an example — ends early, and the failure is reported as "Lexer
  Error: unrecognized character" somewhere further down.
- **Reserved words with no visible role.** `VALUE`, `LABEL`, `ORIGIN`,
  `OVERLAY` and `FORTRAN` are reserved; using one as a parameter or variable
  name gives a parser error naming the token.
- **`CONCAT`'s destination must be a bare variable**, never a record field and
  never a `VAR` parameter. Build the string in a local and assign it after.
- **`ADR` takes a bare identifier only** — never `ADR rec.field`.
- **Pointers compare only with `=` and `<>`.** There is no pointer subtraction
  and no relational comparison, so a C-style `while (p < end)` walk does not
  compile. Carry an `INTEGER32` index against a base pointer instead.
- **The only pointer arithmetic is `pointer + integer`** (either order). It
  steps by whole pointee elements (bytes for `ADRMEM`), never traps and is
  not subject to `$MATHCK`; the offset keeps its own signedness, so a `WORD`
  offset above 32767 moves forward. `p - 1`, `p * 2` and a `REAL` offset are
  rejected. Arithmetic inside the offset expression is checked as usual, and
  so is Pascal arithmetic on values returned by `[C]` routines.
- **Structurally identical string types are interchangeable when their
  capacities match.** `Str255`, `ByteStr` and `ArgStr` (all `LSTRING(255)`,
  each declared in its own unit) assign to one another and pass as `VAR` or
  value parameters with no copy. A capacity mismatch (`LSTRING(255)` into
  `LSTRING(100)`) is still rejected, and an `LSTRING(n)` never mixes with a
  fixed `STRING(n)`. This matches the reference type system, which is
  structural rather than name-based.
- **A `STRING(n)` is exactly n characters**, like `PACKED ARRAY [1..n] OF
  CHAR`. A shorter string literal does not fit: `s := 'ten'` for `s:
  STRING(10)` is rejected with `string literal length does not match STRING
  capacity`. Use `LSTRING(n)`, which carries a length byte in element `0` and
  accepts any length up to `n`; a `STRING(n)` or `CHAR` value converts to
  `LSTRING` automatically on assignment.
- **`CONST` accepts literals, named constants, and `WRD`/`BYWORD` constant
  constructors.** Multi-character string constants are supported. `WRD(x)`
  and `BYWORD(hi, lo)` are the only function-shaped forms in the vintage
  `constant` grammar; ordinary calls, including `ORD`, `CHR`, `SUCC`, and
  `PRED`, are not valid `CONST` values.
- **A `CASE` label range (`1 .. 3:`) is not lowered [both].** The selector
  itself may be any ordinal — every integer width, `CHAR`, `BOOLEAN`, an
  enumerated type — and labels of a narrower type than the selector are
  adapted to it, but each label must still be a single constant. Write the
  labels out (`1, 2, 3:`) or use `IF`.
- **`REAL` does not narrow to `REAL32` implicitly [extended].** `f := d` for
  `f: REAL32; d: REAL` is rejected by both compilers, and there is no
  narrowing conversion to write instead: keep the value in `REAL32` from the
  start (a `REAL32` variable assigned a literal, or `REAL32` arithmetic).
  The native typechecker has no `REAL32` of its own — it models it as `REAL`
  — so the rejection comes from codegen, as `assignment type mismatch for:
  <name>` with no line number.
- **A nested routine cannot read an enclosing routine's local [both].**
  Neither compiler emits a static link, so an inner `PROCEDURE`/`FUNCTION`
  reaches only its own parameters and locals and the compiland's file-level
  variables. Reading an outer local fails in LLVM verification ("Referring
  to an instruction in another function"), naming neither routine. Pass the
  value as a parameter, or lift it to a file-level variable.
- **There is no implicit `INTEGER64` to `REAL` conversion [extended]**, and
  `FLOAT()` is an explicit numeric-to-REAL conversion, not an implicit one.
  The runtime's
  `pas_int64_to_double` exists because there is no way to write that
  conversion in Pascal.

## Checklist before committing Pascal in this tree

1. For extended code, every length, offset, capacity, byte count and file size
   is `INTEGER32`. A vintage program has no such type; keep its values within
   `INTEGER` or use an appropriate vintage representation.
2. No `TRUNC` or `ROUND` on a value that can exceed 32767 **[both]**.
3. A literal assigned to a plain `INTEGER` is inside `-32768..32767`.
4. Extended code uses an explicit `--dialect extended` option.
5. `make test-bootstrap` reaches a byte-identical `gen3` and `gen4`.
