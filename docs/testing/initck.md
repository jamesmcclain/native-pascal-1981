# INITCK tests

The INITCK support boundary and the suites that pin it. The test suites themselves are described in
[tests/README.md](../../tests/README.md).

## INITCK support boundary

`./tests/contract/initck_definite.sh` (in `make test`) tests compiler-owned
scalar-local definite-initialization proofs. O0 IR counts pin removed guards
for direct assignments, known unchecked producers, BOOLEAN/CHAR locals and
both-arm IF joins, while retaining shadow slots/stores and output-call guards.
Both dialects at O0/O1/O2/O3 require exact initialized output and runtime failure
before derived output for a missing branch, GOTO bypass, zero-iteration loop, unchecked
unknown copy, and function-call mutation through VAR. Each unknown read retains
a metadata guard before its native load; disabled bad twins are compile-only.
The suite owns `tests/contract/fixtures/initck_definite_fail.pas` (OneBranch) and the four
`tests/contract/fixtures/initck_definite_fail_{goto_skip,zero_loop,unchecked_copy,call_effect}.pas`
variants. These retain the same declarations and source line layout, changing
only the final probe invocation; keep them synchronized when maintaining the
shared cases. The original OneBranch fixture also supplies the O0 structural
IR oracle for all five routines. These are not runnable golden tests. Validate
changes with `./tests/contract/initck_definite.sh`.
The pass is conservative: calls, loops, selected destinations and unknown syntax
kill facts, GOTO/labels disable it, and aggregate/heap/formal/result guards stay.

`./tests/contract/initck_validation.sh` (in `make test`) is a focused
release gate using persistent `tests/contract/fixtures/initck_validation_*.pas`.
The values fixture accepts INTEGER zero and `-32768`, FALSE, CHAR `CHR(0)`,
and NIL after both checked and unchecked writes. Record/array transfers, heap
referents, and scalar value arguments/formals/results also accept zero and
`-32768`, proving initializedness is not encoded by reserved data values.
Success output is identical with checking on/off; a checked unset value actual
must fail even when its callee ignores it, with one exact diagnostic and no
later output. Both dialects run at O0/O1/O2/O3. The mixed fixtures combine
partial records/array elements, unchecked state-preserving aggregate copies,
forwarded VAR writes, CONST and WITH aliases, value arguments and scalar
results, and INITCK/DEBUG/PUSH/POP regions. Reading an initialized leaf of a
partial record succeeds; filling its missing leaf through VAR permits a checked
whole-value call. A partial unchecked copy/value argument must still fail at a
callee's checked CONST-alias read of the missing leaf, after exact prefix output.
O0 IR places the metadata branch and
terminating failure before the first native load and the ignored-argument call.
Disabled twins have no failure calls; both disabled unset-read twins are compiled
to IR only, never linked or executed. The old metadata-only on/off identical-IR
oracle is replaced by O0 assertions for located guards on scalar/pointer reads,
whole-record copies, array elements, heap leaves, formals and results. Both
on/off twins must retain scalar/aggregate shadow slots, copy state propagation,
heap registration/lookup/retirement and result-state publication: disabling a
guard is not disabling producers. Legacy/missing-read-snapshot opt-outs in
`initck_contract.sh` still compare identical IR only where no checked read
remains. Runtime failure requires nonzero status, not a platform-specific abort
code.

`./tests/contract/initck_abi.sh` (in `make test`) verifies initialized
on/off twin output in both dialects at O0/O1/O2/O3. O0 IR pins every tested
Pascal definition and call: scalar, value/VAR/CONST descriptor transport,
register-coerced descriptor/record results, and byval/sret descriptor pairs.
It also pins separate `{ ptr, i64 }` storage, alignment and whole descriptor
loads/stores; runtime SIZEOF is 16/16/32 for descriptor/holder/pair. Checked
reads really emit guards; disabled twins do not. Descriptor/aggregate result
boundaries remain explicitly INITCK- in both twins: this verifies ABI and
initialized output compatibility, not unsupported result enforcement. The
broader `descriptor_contract.sh` retains global layout, register-budget,
foreign and DEVICE ABI coverage.

`./tests/contract/initck_contract.sh` (in `make test`) checks boolean
INITCK metadata in lexer tokens, parser ASTs, and typed ASTs. It covers
standalone toggles, DEBUG coupling and overrides, PUSH/POP, `$IF INITCK`, and
declaration-boundary snapshots. Enabling a directive alone is silent; enabled
unsupported consumers fail in codegen before IR publication. Public-driver
probes distinguish enabled guard IR from disabled IR. A warning-replacement
gate in both dialects at O0/O2 requires unsupported declarations and literal
writes to remain silent, even across repeated INITCK/DEBUG/PUSH/POP transitions.
Two unsupported enabled reads must produce exactly the first located boundary
error and no IR, not a directive warning or diagnostic flood; disabled twins
compile silently. The external-boundary matrix separately pins each reachable
remaining category and its location, including CPU and NVPTX DEVICE consumers.
The disabled uninitialized read is compiled only, never executed.

`./tests/contract/initck_state.sh` (in `make test`) tests scalar-local
shadow allocation/reset independently of enabled guards. Exact O0 IR asserts flag-independent host
INTEGER/BOOLEAN/CHAR shadow allocas and false prologue stores, excluding globals,
formals, other types, and CPU/NVPTX DEVICE locals. Test-only IR instrumentation
reads and poisons **metadata**, never uninitialized Pascal bytes, to verify fresh
and distinct recursive activations, nested/sibling scopes, and repeated calls at
O0/O2. The fixture also pins supported direct-assignment state stores.

`./tests/contract/initck_scalar.sh` tests successful INTEGER/BOOLEAN/CHAR assignments,
zero and literal -32768, disabled producers, conditions, skipped writes, fresh
recursive activations, early returns, REPEAT read-before-write, DEBUG overrides
and nested PUSH/POP. Repeated early-return invocations exercise both bypassed
uninitialized storage (no read) and initialized loop paths; negative cases cover
untaken conditional/WHILE writers, a recursive early-return branch with fresh
unset storage, and guard re-enablement through POP and DEBUG. Positive programs
run with checking on/off in both dialects at O0/O2. A dedicated disabled-write
matrix covers all three scalar types declared under INITCK+, both taken branches,
unchecked initialized RHS/copies, repeated calls, and disabled overwrites after
checked reads, in both dialects at O0/O2. A skipped disabled writer must leave
state unset for the next enabled read. O0/O2 failures must emit
one exact INITCK error with local name and read-site line/column and no output
after the failed read. Parser/typed metadata checks pin a parenthesized read's
identifier coordinates; O0/O2 tests cover source-aware and name-only older-AST
failures. Direct runtime probes distinguish INITCK, existing SUPER NIL-pointer,
and bounds diagnostics (not a NILCK directive coverage claim). O0 IR checks place
state publication after the data store and the metadata branch/failure block
before each native load; disabled and legacy bad reads remain compile-only.
Boundary cases cover globals, REAL, enums/subranges, a REAL heap
referent, a dereferenced global pointer, an array with
REAL elements, a record with a REAL field, the address of a WITH-bound
field, a FILE OF REAL buffer, LSTRINGs, sets, WITH over an untracked record, a local mentioned
under a nested WITH whose target fields are not evident, enabled END/RETURN of a REAL
function, a builtin call consumer, and CPU DEVICE. Each enabled case rejects with one exact category
line and no published IR at O0/O2; its disabled counterpart must compile cleanly
but is never executed. Late, disabled and untaken escapes still exclude
storage for the whole routine (`ADR` of a local or formal is a release at its
evaluation instead: `initck_external.sh`). Actual enclosing-local captures remain a separate
native compiler limitation, not a supported alias case. Broader producer, alias,
result and representation enforcement remains outstanding.

`./tests/contract/initck_producers.sh` (in `make test`) covers scalar
producers beyond literal assignment. Unchecked copies, expressions, chains and
comparisons of unset tracked locals leave the destination unset (exact O0/O2
failure at the later checked read). Initialized copies and overwrites of a
tainted slot succeed in both dialects at O0/O2, and an O0 IR check pins the
state accumulator. Stdin READ/READLN of INTEGER/CHAR/BOOLEAN initializes only
its destinations. An O0 IR check pins the status-gated select for file READ,
because file error trapping cannot be enabled from Pascal source. FOR control
is covered for TO/DOWNTO, CHAR/BOOLEAN, BREAK/GOTO retention and zero
iterations. Reads after natural termination, after a zero-iteration loop, and
from an unchecked unset initial value fail exactly. FOR over a global or an
INTEGER32 control variable under INITCK+ compiles without a boundary error.

`./tests/contract/initck_routines.sh` (in `make test`) is the routine-boundary
preservation gate. A correctly initialized program passes 0, FALSE, CHR(0) and
`-32768` through value, VAR and CONST formals, recurses and nests, and calls
functions that never assign their result. Those return the retained native
zero/default bytes for INTEGER, BOOLEAN, CHAR, REAL, pointer, coerced-record and
sret-record results, which is the agreed INITCK-off behavior. Output must match
exactly in both dialects at O0/O2, unannotated and with INITCK+ at each enabled
read the current slice accepts. Every routine definition and Pascal call site is
pinned at O0 and must be identical in both variants, so instrumentation adds no
hidden parameters or result changes. The suite owns
`tests/contract/fixtures/initck_routines_{plain,checked}.pas`; maintain them together, preserving
INITCK-off at unassigned or unsupported/default returns. The plain fixture
retains the former expansion's spacing, including two spaces on blank line 35,
for byte equivalence. These are suite inputs, not runnable golden tests.
Validate changes with `./tests/contract/initck_routines.sh`.
The same script covers value formals and tracked results. A fully checked program passes 0, FALSE, CHR(0) and `-32768`
through formals and results, nests calls, recurses with an early RETURN, and
hands unset actuals to callees that ignore or overwrite them, in both dialects
at O0/O2. Exact O0/O2 failures cover a checked unset actual at the caller, an
unchecked unset actual read in the callee or copied to a callee local, an
unassigned result at an enabled END or RETURN, an unchecked return tainting
the caller, a result assigned on one path only, a fresh recursive result, and
nested calls that must not cross argument states. An O0 IR check pins the side
channel: the callee copies and clears its slot before any call, the caller
publishes after evaluating all actuals, then resets the result flag, then
clears after the call, and untracked REAL formals get no slot. VAR/CONST coverage
is also exact, in both dialects at O0/O2. Callee writes initialize the caller's
locals, forwarding works, `swap(x, x)` shares one binding, and BOOLEAN/CHAR
formals are covered. A global binds a private initialized slot. An
address-escaped formal releases its caller's slot. A C-implemented plain EXTERN
that never clears its slot cannot disturb the next call. Exact failures cover
VAR and CONST reads of an unset caller local, an unchecked copy through CONST
into VAR, forwarding, and a callee that writes on one path only. An O0 IR check
shows that a tracked VAR actual publishes the caller's own state slot (a
global publishes nothing) and that the callee guards and writes through its
selected binding. Nested routines and WITH are also covered in both dialects at
O0/O2. Same-name formals and locals two levels deep leave the enclosing local
tracked. Locals are written and checked inside WITH bodies (single, multiple
and VAR-formal targets) while a same-name field shadows without touching the
local. Exact failures cover an unset local read inside a WITH body, a nested
routine's own unset local, and an enclosing local left unset by a nested
routine. The suite owns `tests/contract/fixtures/initck_routines_{withread,nestedread,nestedother}.pas`
for these three failures: retain body line 9 and nested declaration line 4,
which feed the exact diagnostic oracle. Do not run their unchecked bad twins.
An enabled captured read is the exact `global or captured storage`
boundary. With INITCK disabled, the pre-existing capture limitation still
rejects the program, and INITCK adds nothing to that error.

`./tests/contract/initck_aggregates.sh` (in `make test`) covers INITCK
aggregates: fixed ARRAYs and RECORDs of INTEGER/BOOLEAN/CHAR leaves, nested
arrays of records and records of arrays, CHAR-indexed arrays and dynamic
indices. Positive programs run in both dialects at O0/O2 with zero and
`-32768` values, disabled component writes, READ/READLN into components and
unchecked component copies. Exact O0/O2 failures show that one write never
initializes a neighbor (element, field, nested, dynamic, two-level and
computed-index cases), that each recursive activation starts unset, that an
unchecked unset component taints a scalar or component copy, that an index
with unset state taints the selected value, and that READ initializes only its
own destination. An out-of-range index reports the bounds error before INITCK,
and an O0 IR check orders bounds check, element-shadow GEP, metadata branch
and failure call before the native element load. Aggregate copies: a positive
program in both dialects at O0/O2 performs checked whole, element and
self-copies, an unchecked partial array copy that keeps per-leaf states, a
global round trip, a call result, and checked and transported value actuals.
Exact failures cover a checked partial source, unchecked partial, self and
element copies read later, a checked partial sub-aggregate source, a checked
partial value actual at the caller, an unchecked one failing at the callee's
own read, and an index with unset state unsetting the copy. An O0 IR check
orders the whole-shadow check before the source load and each leaf-state
transfer after its data store. Variant records: a positive program (both
dialects, O0/O2) checks a transfer with fixed fields plus one complete
alternative, a tag change that keeps the written alternative readable, an
empty alternative, element-wise checks of arrays of variant records (tagged
and tagless) and an unchecked copy keeping per-alternative states. Exact
failures cover reading another alternative's overlapping field (tagged and
tagless punning), a tag and an alternative not initializing each other, and
checked transfers with an incomplete alternative, an unset tag, or an array
element with no complete alternative. Aliases: a positive program (both
dialects, O0/O2) shares leaf, whole, sub-aggregate and forwarded VAR/CONST
bindings, runs WITH over a record, a selected element and a computed-index
element, binds a global privately and releases an escaped formal. Exact
failures cover a callee's checked read of an unset bound leaf, a callee
writing one element, a checked whole copy of a partially written VAR formal,
a CONST component read, and WITH writes leaving siblings unset (after the
WITH, inside it as `field y`, and through a selected sub-record). WITH-bound
names resolve to fields before routine locals: a tracked field wins over a
same-named REAL local, and an untracked LSTRING field is an exact boundary for
output and CONCAT. Representations: PACKED arrays and records are rejected by
codegen identically with INITCK on and off; LSTRING (element and `.LEN`),
STRING, SET, VECTOR and BOOLEAN-vector components, and a record holding an
LSTRING, are exact O0/O2 boundaries whose INITCK-disabled twins compile
cleanly. Single evaluation: a side-effecting index function is
called exactly once per designator across checked reads, writes, READ, VAR
bindings, WITH targets, both sides of an aggregate copy and an INDEXCK-
read (both dialects, O0/O2); failing INITCK and bounds checks follow exactly
one call; and an O0 IR check shows that without INDEXCK the element shadow
reuses the data GEP's own offset value. Boundary cases for
aggregates with untracked leaves, whole-aggregate uses and selected VAR
actuals are in `initck_scalar.sh`.

`./tests/contract/initck_heap.sh` (in `make test`) covers INITCK pointers
and heap storage. Pointer values: a positive program (both dialects, O0/O2,
INITCK+ wherever the slice supports it) initializes pointers by NEW, NEW
through a VAR formal and NEW of a record field, copies, compares against NIL
and each other, passes and returns them, and DISPOSEs them. Exact O0/O2
failures read an unset pointer in a comparison, at a dereference in an
assignment target (reported at the `^`), as a selected record field, in
DISPOSE (a local and an array element), after an unchecked copy, after NEW
on an untaken branch, in a callee after an unchecked value actual, and as an
unassigned pointer result. An O0 IR check orders NEW's pointer store before
its state publication and the pointer guard before the native pointer load.
Heap referents of ordinary NEW: a positive program (both dialects, O0/O2,
INITCK+ throughout) writes and reads record, scalar and array referents
including zero, FALSE and `-32768`, builds and walks a linked list, shares
state through a second pointer, initializes through WITH-bound fields and
VAR bindings, and copies whole heap sub-records and passes them by value; a
second program shows a disabled write and an unchecked partial heap copy
keeping per-leaf state. Exact O0/O2 failures: a fresh referent, a sibling
field, an unset heap pointer field at its `^`, a renewed referent, a read
through an aliasing pointer, array and scalar referents, a WITH-bound field,
a callee's VAR read, a checked whole copy, an unchecked partial copy read
later, and an unchecked heap read tainting a local. Releases (extended
dialect, O0/O2): C-allocated memory, and referents written by C after a
WITH-bound field's ADR, a pointer-to-ADRMEM conversion and an ADRMEM actual,
read checked without false positives; an executed `[C]` routine writes a
referent through its pointer argument. An O0 IR check orders allocation,
state registration, pointer publication, and lookup and guard before the
native load. SUPER ARRAY descriptors (extended dialect, O0/O2): a positive
program initializes descriptors by NEW, NEW through a VAR formal into a
record field, a function result and UNSAFESUPER, copies, compares and passes
them, and reads them by UPPER and UNSAFERAW. Exact failures read an unset
descriptor in UPPER (at its `^`), a comparison, DISPOSE, an element store,
after an unchecked copy, as a record field, in a callee and as an unassigned
result. An O0 IR check orders NEW's descriptor store before its state and the
descriptor guard before the descriptor load and UPPER's NIL check. Heap SUPER
ARRAY elements (extended, O0/O2): a positive program writes and reads INTEGER
elements from a negative lower bound (including `-32768`), record and pointer
elements, swaps elements through VAR formals, fills them in a callee through a
copied descriptor, binds one with WITH, and reads elements after VSTORE
released the allocation. Exact failures: a fresh element, a neighbor, a
sibling field, a renewed allocation, a read through an aliasing descriptor, a
callee's VAR read, a WITH-bound field and an unchecked element read tainting a
local. Elements exported with UNSAFERAW and written by C, and C memory
imported with UNSAFESUPER, read checked without false positives. An O0 IR
check orders `pas_super_new`, the `count * leaves` registration and the
descriptor publication, and the bounds check, per-element lookup and guard
before the native element load. DISPOSE: a NEW after DISPOSE fails as a fresh referent; C memory that
reuses a disposed address (glibc does) reads without a false positive, and
deleting the retirement call from the IR (a mutation check, run whenever the
address was reused) makes it fail; an O0 IR check orders the pointer guard,
pointer load, retirement and `free` for a pointer and a descriptor.
Nesting and aliases (extended, O0/O2): a recursive binary tree built and
summed with checked reads, a pointer to a pointer, a heap record holding a
SUPER ARRAY descriptor and an array of pointers, whole referents bound to
VAR and CONST formals and passed by value, a heap variant record written
through both alternatives, and a nested WITH over heap records (unchecked;
the released referent then reads checked without failing). Exact failures:
an unset pointer inside a referent at its `^`, an unset descriptor in a
referent, an unset element behind it, an unset pointer two levels deep, a
field a VAR callee did not write, a CONST callee's read, a partial value
actual, and an unwritten variant alternative and tag.
Allocation failure (`tests/contract/fixtures/initck_heap_publication.c`, linker-wrapped
malloc/calloc/abort, O0/O2): a failed ordinary NEW data allocation, its state
allocation, a failed SUPER ARRAY NEW data allocation, its state allocation,
and a failed registry-table growth each abort with their exact diagnostic
while both destinations and the old referents' state are unchanged and any
successful data allocation stays unregistered; an IR check places the
ordinary NEW failure branch before registration and publication.
`tests/contract/fixtures/initck_heap_runtime.c` unit-tests the registry (ranges, mismatched
counts, releases, retirement, reuse, growth with tombstones, scratch, and the
per-site fallback runs of `pas_initck_heap_at`/`pas_initck_heap_part_at`).
Exact boundaries: a global pointer dereferenced, a referent with a REAL field, a field read
inside a WITH whose body releases its referent, and a REAL SUPER ARRAY
element.

`./tests/contract/initck_external.sh` (in `make test`) covers INITCK at
external boundaries, linking generated IR with a C helper. C calls: a `[C]`
VAR/CONST binding initializes exactly the bound storage (a scalar, a whole
array, one element; a CONST binding of a written local) and nothing else
(exact failures for the sibling element and an unrelated local). Plain
EXTERNs implemented in C (no handshake acknowledgement) release their VAR
binding and a typed pointer's referent after the call and return an
initialized result; a Pascal routine C calls back during such a call ignores
the caller's published slots. Four IR mutations (no release, no referent
release, an unconditional tag match, no acknowledgement test) each turn the
positive program into its exact false positive. A separately compiled MODULE
behind plain EXTERN declarations acknowledges, so its unwritten VAR binding,
unset result and unwritten referent still fail exactly. An O0 IR check pins
the caller's tag/flag/release order, the `[C]` fill before the call and the
callee's tag comparison before its first slot load. Raw addresses (`raw`,
O0/O2): `fillc(ADR flags, ...)`, a write through a typed pointer converted
from `ADR x`, `ADR` of a VAR formal, an address-taken FOR control variable
written after natural exit, an address-taken pointer local, descriptors
passed by value and by VAR to a C plain EXTERN that writes their elements,
and a `[C]` ADRMEM result, all checked. Exact failures: a read before the
`ADR`, an untaken `ADR`, another local, an unset ADRMEM read and an unset
ADRMEM transported to a callee. Mutations removing the `ADR` release or the
descriptor release restore false positives; an IR twin without the `ADR`
keeps the FOR natural-exit unset. Files (`files`, O0/O2, INITCK+): REWRITE/
PUT/RESET/GET/EOF/EOLN/CLOSE/WRITELN on local and global files, `-32768` and
0 through a FILE OF INTEGER, a buffer written by a `[C]` VAR binding, a record
buffer written and copied whole, and a TEXT buffer read and consumed. Exact
failures: an unwritten buffer read and PUT, PUT after PUT, a partial record
buffer PUT and copied, and the buffer at EOF; an IR check places the state
beside the buffer and the PUT guard before the runtime's write. FILE OF REAL
is the `filereal` boundary in `initck_scalar.sh`. DEVICE: a CPU-device host
program (O0/O2, INITCK+) launches a kernel that writes a never-written NEW
referent and reads it back checked, and round-trips an array through
DEVALLOC/DEVCOPYTO/DEVCOPYFROM/DEVFREE; IR places the referent release
before `pas_dev_launch`. An enabled read in a CPU and an NVPTX DEVICE
compiland is exactly `DEVICE code` with no IR. The compile-only input is
`tests/contract/fixtures/initck_external_device_read.pas`, owned by this suite; it disables
INITCK after the read, before closing END. The distinct
`tests/contract/fixtures/initck_scalar_device_read.pas`, owned by `initck_scalar.sh`, leaves
INITCK enabled at END and has a compile-only disabled twin. Keep their line
layout stable: the external suite checks the read's line 11 coordinate.
Neither fixture is a runnable golden test. Run their owning suites through
`./tests/contract/initck_external.sh` and
`./tests/contract/initck_scalar.sh` when maintaining them.
Diagnostics (`bnd`, O0/O2):
every reachable boundary category gives its exact line with the consuming
token's location and no IR, and its INITCK-disabled twin compiles cleanly;
`selected storage` is defensive and documented as unreachable. Review
regressions (O0/O2): VAR aliases of two distinct released heap records and
of two distinct C cells keep separate state (`untracked`); a `[C]` VAR
binding, a pointer value handed to `[C]` and an `ADR` actual take effect at
the call, so a later actual reading the same storage fails exactly when it
is unset (`callorder`, `orderbad`); a `[C]` result and a Pascal result
through an untracked REAL formal stay initialized after an unchecked unset
actual (`argscope`); a checked main-body read of a program variable is the
`global or captured storage` boundary (`mainbnd`). The other
scripts' boundary loops compare categories with the location stripped.

INITCK scalar producer and calling-boundary matrix. Every rule has executed
positive and exact negative coverage at O0/O2 unless marked IR/compile-only.
Scripts: S = `initck_scalar.sh`, P = `initck_producers.sh`, R =
`initck_routines.sh`, X = `initck_external.sh`.

| Rule | Positive | Negative |
|---|---|---|
| Direct assignment, flag-independent | S good/disabled-writes | S expression/skipped/recursion |
| Unchecked copy carries source state | P copy-ok | P copy-bad (6 shapes) |
| READ/READLN destination (stdin) | P read-ok, formal-ok | P read-bad; file trap IR-only |
| FOR control; unset after natural exit | P for-ok, formal-ok | P for-bad (6), formal-bad (VAR) |
| Value formal receives actual state | R transport-ok | R formal, formalcopy, nested |
| Checked actual read at caller | R transport-ok | R actual; `[C]` actual in cinterop |
| Result: name assignment, RETURN/END | R transport-ok, sites-ok | R endresult/returnresult/partial/recursion, debugend/pushreturn |
| Unchecked return taints caller | R transport-ok | R taintresult |
| VAR/CONST share caller state | R var-ok, recvar-ok | R varread/constread/varcopy/forward/partial, recvar-bad |
| Untracked binding / escaped formal | R var-ok (global, zap) | n/a (assumed initialized) |
| Uninstrumented C caller/callee | R cinterop (mutation-checked) | R cinterop `[C]` actual |
| Nested redeclaration, WITH locals | R scope-ok | R withread/nestedread/nestedother |
| Captures, untracked results | n/a | R capture; S boundaries |
| `[C]` VAR/CONST binding, C-implemented EXTERN | X cwrite, modok | X sibling/other, modvar/modres/modptr, mutations |
| `ADR` release, ADRMEM values, descriptors to C | X raw | X before/untaken/other/adrmem/transport, mutations |
| File names, buffer fill/EOF/PUT, buffer writes | X files | X unwritten/put/putput/partialput/partialread/eof; S filereal |
| Host LAUNCH/device builtins; DEVICE compilands | X devhost | X devread (CPU, NVPTX); S device |
| Boundary categories and locations | n/a | X bnd (11 categories), devread |
| Legacy AST without return snapshots | R legacyret (no guard) | n/a (opt-out) |
| Signatures/defaults preserved | R plain/checked gate | n/a |

`tests/contract/fixtures/initck_reads.pas` and the native `initck_read_check.pas` probe
also check independent `read_flags` snapshots on expression/designator nodes,
call and UPPER consumers, index and dereference selectors, assignment and WITH
targets, and transparent parentheses. Directives inside statements deliberately
make consumer flags differ from declaration, statement-entry, and later-token
flags. Parser and typed snapshots must match the exact oracle; codegen rejects
the resulting enabled unsupported reads. These are compile-only metadata tests, not initializedness
tests. Frozen historical AST comparisons ignore this new native metadata key;
the focused INITCK test checks it explicitly.

`tests/contract/fixtures/initck_read_toggles.pas` adds exact, separate declaration and
read-site oracles for globals and routine locals declared under both INITCK
states. Repeated uses of each slot toggle within one statement; assignment,
condition, and call operands also differ from statement-entry flags. A directive
after an emitted assignment-target identifier changes the RHS snapshot, not the
target's. Both parser and typed ASTs are checked; codegen rejects the enabled
unsupported consumers. The uninitialized reads are never executed.

`tests/contract/fixtures/initck_read_transitions.pas` extends the actual-read oracle to
DEBUG coupling/recoupling, explicit overrides in both directions, nested
PUSH/POP, both `$IF INITCK` branches, and nested skipped directives/includes.
Two active include fragments carry reads and flag changes back to their caller,
including a PUSH in one include restored by POP in the other. A skipped missing
include must not be opened. DEBUG after an emitted identifier changes only the
next consumer. Exact parser/typed snapshots and codegen boundary rejection are checked;
these fixtures remain compile-only and do not claim runtime protection.

The INITCK contract script also strips all or alternating `read_flags` from
parser and typed AST inputs to simulate legacy and mixed producers. Rechecking
must preserve absent and explicit snapshots independently, even with enabled
declaration/statement flags still present. Codegen accepts each input and emits
identical unchecked IR for these particular retained non-consuming snapshots.
Missing snapshots are a legacy unchecked opt-out,
never inferred enabled reads; no uninitialized probe is executed.
