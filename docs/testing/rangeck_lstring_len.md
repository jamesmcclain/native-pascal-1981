# LSTRING length-byte publication checks

Run after `make`:

```sh
tests/contract/rangeck_lstring_len.sh
```

The suite covers the length-byte portion of the LSTRING RANGECK contract
(assignment, READ and VAR CHAR actuals), not all string producers or unconditional memory safety.

- Both dialects, O0–O3: zero and exact capacity, zero-capacity storage,
  capacity 256 with byte value 255, legal truncation/extension, and ordinary
  payload bytes whose character values exceed the declared capacity.
- Enabled failures: capacity+1 and byte value 200, including array, pointer,
  record, WITH-field and VAR-LSTRING-formal targets. RHS reads of another
  LSTRING's length must not replace the saved target capacity. Indirect
  failures run with both MATHCK settings.
- Index-zero aliases: constant/dynamic INTEGER, WORD, CHAR, BOOLEAN and enum
  zero indexes. Nested array/pointer selection is covered; nonzero indexes
  must not receive a length-value restriction.
- Other length-byte writers: stdin and file `READ` into `.LEN`, constant
  and dynamic index zero, and a VAR CHAR formal bound to `.LEN` or a
  dynamic index zero, directly or through a pointer. A READ is checked
  after a successful conversion, like a subrange READ; a VAR actual is
  checked when the call returns, under the call site's RANGECK. Payload
  bytes written the same ways, and in-capacity lengths, pass.
- RANGECK- invalid lengths are inspected as guard-free IR only. They are
  never passed to later string operations or executed as unchecked tests.
- Assignment first-token snapshots, opposite RHS directives, nested/sibling
  restoration, and enabled legacy inheritance without assignment snapshots.
- O0 IR: one target/source call each, target before source, capacity check
  before store, and failure blocks with no stores.
- Test-only abort wrapping checks all eight bytes of two adjacent LSTRING
  slots, once-only target indexes/RHS, and retained side effects. Both `.LEN`
  and dynamic index-zero variants run through clang O0–O3. No test hook is
  linked into production runtime code.
- CPU DEVICE guard and runtime failure; NVPTX compile-only confirmation of
  its existing host-runtime exclusion.

Failures call `pas_lstring_length_error` in `runtime/subrange.c`: stdout and
stderr are flushed, the error is `runtime error: RANGECK LSTRING length V
exceeds capacity CAP at line L column C`, located at the target designator,
and the process aborts.
The effective capacity is `min(declared capacity, 255)`. `.LEN` stays CHAR;
its containing capacity is an address-selection fact, not a new ABI type.
Compiler-generated destination bytes are not published on failure; user
side effects during target/RHS evaluation are not rolled back.

Known boundaries remain outside this slice: general STRING/LSTRING index
bounds, CHAR aliases made through ADR or other raw addresses, foreign/raw
writes,
whole-string copies/value parameters and other mutating builtins. The
broader R5 audit must not be checked off on the strength of these tests.
