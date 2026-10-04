# Dialect notes: dialects, widths, and the things that fail silently

This is the document to read before writing Pascal in this repository. It
records the parts of the 1981 IBM Pascal dialect that do not behave the way a
modern Pascal or C programmer expects, with a bias toward the ones that fail
*silently* — no error, no warning, just a wrong number somewhere downstream.

Everything here has been verified against the native compiler in this tree
rather than inferred from its sources.

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
bin/pascal1981 -S tests/golden/01_hello.pas -o /tmp/hello.ll
bin/pascal1981 --dialect extended -S tests/golden/01_hello.pas -o /tmp/hello.ll
```

The standalone parser, typechecker, and code generator also default to
`vintage`. These stages accept data only on standard input. An explicit
extended pipeline has this form:

```sh
bin/lexer < tests/golden/01_hello.pas |
  bin/parser --dialect extended |
  bin/typechecker --dialect extended |
  bin/codegen --dialect extended > /tmp/hello.ll
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

The old enabled/disabled **identical-IR** expectation applied only to the
metadata-only baseline and is no longer valid for supported checked reads.
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
actual is evaluated (`cadr(ADR x, x)` still checks `x`); `x` stays tracked.
Such a deferred release happens at the call even when the `ADR` was on a
skipped `AND THEN`/`OR ELSE` operand, which can only miss an unset value. A read before that point, an `ADR` on an
untaken path and other variables are still checked, and writes through the
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

## Bound expressions **[native]**

The following describes implemented behavior. Host super-array pointers now use
[the descriptor ABI](host_super_array_abi.md): nonpacked `{ptr, i64}` storage,
16-byte size/stride and 8-byte alignment on x86-64 Linux/SysV. Assignment,
record/array slots, value/reference parameters and function results preserve the
whole value. Native value/result ABI uses two INTEGER eightbytes, or byval/sret
for larger aggregates and register exhaustion. NIL is `{null, 0}`; equality
compares data addresses. The declared lower/index domain stays type metadata.
Same resolved pointer type (including aliases) is required; separately declared
pointer types are not interchangeable. Use a shared named pointer type in
variables, fields and repeated routine headings. Rebuild affected host units.
DEVICE pointers and DEVICE-interface storage remain thin and unchanged.
Host descriptor parameters/results/storage imported into DEVICE code are
explicitly rejected, not silently reinterpreted as thin pointers.

Extended `UNSAFERAW(p)` explicitly exports element data as CPTR/ADRMEM.
`UNSAFESUPER(P, raw, lower, upper)` explicitly imports to descriptor type P;
runtime operands execute once. It requires matching lower, representable/domain-
valid upper, non-NIL aligned data and nonoverflowing extent/address arithmetic,
including under INDEXCK-. Both emit `unsafe-super-array-conversion` warnings
and respect user routine shadowing; vintage and DEVICE uses are rejected.
Import validates metadata, **not capacity, provenance, ownership or lifetime**;
those are unsafe caller warranties. DISPOSE requires an exact compatible native
allocation and an exclusive right to free it. C descriptor signatures, known
slot-address escapes, implicit raw/ADS conversions, pointer arithmetic/ordering,
numeric descriptor I/O and direct descriptor LAUNCH arguments are rejected.

Host SUPER ARRAY NEW evaluates destination selection and upper once, validates
representability/domain and lower <= upper, checks count/bytes in 128-bit
arithmetic, then allocates elements directly. NULL allocation and invalid bounds/
size produce deterministic `runtime error: NEW SUPER ARRAY ...` diagnostics and
abort, even under INDEXCK-. Only success reaches one complete-descriptor store;
the bound expression's own side effects are not rolled back. No element-zeroing
or concurrent atomicity promise. LLVM allocation strides avoid narrow SIZEOF
arithmetic; oversized element layouts, records beyond supported 32-bit field
offsets, dynamic non-pointer element extents and over-aligned (>16) NEW elements
are rejected. Ordinary thin-pointer NEW likewise aborts with `runtime error:
NEW allocation failed` (IBM error 2001, "No Room In Heap") when its allocation
fails, before the destination is written, instead of storing NIL. DISPOSE frees the
unchanged exact data base; aliases are not invalidated or protected from dangling
access. Host `$INDEXCK+` now checks scalar super-array subscripts against the
selected descriptor's declared lower and actual upper in widened signed/
unsigned arithmetic, with the same executed-only constant diagnostic as fixed
arrays; the offset/GEP reuses the checked full-width value and `$INDEXCK-`
suppresses the guard. A checked subscript through a NIL descriptor fails
deterministically (`runtime error: index through NIL super-array pointer`)
before the bound comparison and before any data access; the index expression
has already run exactly once, and whether its side effects happen before the
NIL failure is deliberately not specified. `$INDEXCK` snapshot semantics and
guard-free IR for disabled snapshots are probed for super subscripts in
`tests/indexck_guard_ir.sh`. Borrowed non-pointer formals and dangling-alias
detection remain deferred.

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
[Subrange range checks](#subrange-range-checks). Function call
postfix selectors are supported only inside a bound operand; this does not
make `f(x)^` a general expression elsewhere. Pointer descriptor formals preserve
bounds; borrowed non-pointer super-array formals are explicitly rejected until
their separate view ABI is implemented. The manual does not prescribe this
implementation's NIL diagnostic or side-effect count.

The earlier Python parser accepts only `identifier ["^"]` here. Field,
indexed and call-result selectors, and general expression operands are
native-only. The Python parity suite is disabled (`tests/README.md`).

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
out of range is reported when the store runs, not at compile time. `SUCC`,
`PRED` and arithmetic are not checked themselves; their result is checked
when it is stored.

`{$RANGECK-}` turns the check off for the statements that follow it, and
`{$RANGECK+}` turns it back on. The setting is recorded on assignments,
procedure calls and `CASE` statements. A statement that does not record it,
such as a `FOR` loop or a function call in an `IF` condition, uses the
setting of the last assignment, call or `CASE` compiled before it. Array
indexes are not checked by `$RANGECK` (see `$INDEXCK` below); string
capacities are still unchecked. NVPTX `DEVICE` code has no host-runtime
subrange check; a `DEVICE` compiland targeting the CPU follows the host
`$RANGECK` path.

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

    runtime error: array index V is outside bounds LO..HI

to stderr using the original signed or unsigned index value (including 64-bit
values) and the declared bounds, flushes stderr, then aborts (normally status
134 on Linux). An unchecked constant or variable index emits no fixed-array
guard; this does not make an out-of-bounds access safe. `$RANGECK` does not
control array indexes.

This slice does **not** add checks to `STRING`/`LSTRING` subscripts,
or the capacities of `CONCAT`, `COPYLST`, `COPYSTR` and `INSERT`. Nor does it
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

Note that `INTEGER`'s range is symmetric: `-32768` is not a writable literal.

## Integer constants and context

Native decimal and radix constants from `-32768` through `32767` have type
`INTEGER`. Positive constants from `32768` through `65535` have type `WORD`.
Vintage mode rejects constants outside `-32768..65535`. Accepting `-32768`
is a deliberate modern divergence from IBM: compatibility is for fun, not
pathology, and INTEGER has no reserved INITCK sentinel. Unary minus does not
make `-32768` valid because its operand is already a `WORD` constant.

An `INTEGER` constant can adapt to a `WORD` context. This includes negative
constants. The conversion keeps the 16-bit pattern, so `-1` becomes `65535`.
An `INTEGER` variable does not adapt in this way.

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

`tests/golden/19_wide_int_literals.pas` pins this behavior.

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

**Historical note, because the wrong version of this was believed for a
while:** until recently the native compiler *did* truncate every literal to 16
bits, and it looked exactly like a property of the dialect. It was not. Three
separate places inside the compiler read a literal's value through `TRUNC` or
stored it in a 16-bit field — the parser's token record, `jsonutil`'s
`AddIntField`, and `Real64ToInt64` in the constant folder — so `40000` became
`-25536` on its way into the AST and nothing downstream could recover it. If
you find yourself writing `n := 65; n := n * 1000;` to avoid a wrap, you are
working around a bug that no longer exists.

## `TRUNC` and `ROUND` return `INTEGER`, so they narrow to 16 bits **[both]**

This one is real in both dialects, and it is what caused the bug above. Both produce a 16-bit
result even when assigned to an `INTEGER32`, and for a value outside 16-bit
range the result is not merely wrapped — LLVM's float-to-int conversion is
poison when it does not fit, so it is genuine garbage:

```pascal
r := 100000.0;
n := TRUNC(r);     { observed: 1227885960 }
n := ROUND(r);     { observed: -31072 }
```

Do not use `TRUNC` to read a number out of JSON, a file, or anything else that
can exceed 32767. The runtime provides `pas_cjson_int32`, `pas_cjson_int64`
and `pas_double_to_int64` for exactly this, and `jsonx`'s `JxIntValue`,
`jsonutil`'s `GetInt` and the compiler's own constant folder all go through
them now.

`ORD` does not have this problem: `ORD` of an `INTEGER32` keeps its width.

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

## Native limitations **[native]**

These are implementation limitations, not vintage-language restrictions.

- **Very large unsigned literals [extended].** The JSON AST stores numbers as
  `REAL`, so decimal `WORD64` literals above `2^53` cannot preserve every bit.
  Use `MAXWORD64` for the upper boundary.
- **Array allocation size [both].** Vintage `WORD` bounds through `65535` are
  retained. A large valid range can still request a correspondingly large
  object from LLVM and the linker.

## Other things that cost time **[both, unless marked otherwise]**

None of these are width-related, but all have produced a baffling error at
least once:

- **A single-character quoted literal is a `CHAR`, not a string.** `JxGet(node,
  'x')` fails to typecheck with "Argument type mismatch" against an `LSTRING`
  parameter while `JxGet(node, 'xy')` is fine. The error says nothing about the
  literal.
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
  `FLOAT()` accepts only a plain `INTEGER`. The runtime's
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
