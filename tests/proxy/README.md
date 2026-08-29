# Completion-proxy conformance suite

Differential tests for `tools/pascal1981_completion_proxy.py` and its native
Pascal replacement. Both implementations are driven through the same corpus of
raw HTTP requests against the same deterministic stub backend, so any
difference between their reports is a difference in the proxy.

## Running

```bash
tests/proxy/run.sh                        # the Python reference
tests/proxy/run.sh bin/pascal1981-proxy   # the native port
tests/proxy/run.sh --record               # re-record the golden
```

`run.sh` exits nonzero and prints a per-case diff on any mismatch.

```bash
tests/proxy/oneshot.sh                    # the Pascal client stack, one call
tests/proxy/oneshot.sh --record           # re-record its expected output
```

```bash
tests/proxy/transforms_check.py           # proxycore against the Python it replaces
```

`transforms_check.py` is a differential test of the pure transforms rather
than of the server: it feeds one corpus to both implementations and compares
the answers directly, so the expected values come from the code being
replaced rather than from a recorded file somebody has to keep honest.

```bash
tests/proxy/corpus_smoke.py               # 64 realistic requests, via the stub
tests/proxy/corpus_smoke.py --base-url URL  # ... against a real backend
tests/proxy/corpus_smoke.py --reference   # no proxy, no model: compile the corpus
```

`--reference` is the compiler's own regression test as much as the corpus's:
every item's recorded continuation is a real program, and each of the two
compiler gaps this mode has turned up so far -- LSTRING's `.LEN` and a
CHAR-keyed `CASE` -- was a construct nothing else in the tree used.

`corpus_smoke.py` answers the question the conformance suite structurally
cannot: not "does this behave like the implementation it replaces", but "does
it work". The conformance backend is a stub that returns one canned reply to
every request, its buffers are a few lines long and its limit is 1024
characters; a proxy can pass all 47 cases and still fall over on a real 4 KB
buffer or return nothing usable from a real model. Nothing here is asserted
about completion *quality* -- a live model returns different text every run --
so it exits nonzero only on a protocol failure.

`oneshot.sh` is narrower and answers a different question: not "does the proxy
behave", but "can Pascal talk to an OpenAI-compatible backend at all". It
builds `oneshot.pas` and makes one `/chat/completions` call per reply shape
against the same stub. It lives here rather than in `tests/integration/`
because it needs the Python stub running alongside it, which `tests/run.sh`
has no way to start.

## Layout

- `stub_upstream.py` — a fake OpenAI-compatible backend. Deterministic by
  design: a real model returns different text every run, which would make
  differential testing impossible. A case picks its upstream reply by
  embedding `@@SCENARIO:<name>@@` in the buffer it sends, because the proxy
  forwards none of the client's headers upstream — the buffer text is the only
  channel a case has. The marker must sit *before* the cursor, since the proxy
  sends only the text preceding it. `GET /_last` returns the most recent
  request the stub received, which is how the outgoing payload shape is
  checked. `--calibrate-ok` makes exactly one `reasoning_effort` value answer,
  which is how `--reasoning-effort auto` is pinned down.
- `cases.py` — 43 cases as raw bytes. Raw bytes rather than a client library
  because much of the contract lives in malformed requests (a non-numeric
  `Content-Length`, a truncated body, invalid UTF-8) that a client library
  would refuse to send. Every case carries a note saying what it pins and why.
- `run_conformance.py` — starts the stub and the implementation, replays the
  corpus, and writes a normalized report. It owns the implementation's flags
  itself, so both implementations are configured identically by construction
  and a mismatch can never be an artefact of how they were started. Also runs
  two phases the corpus cannot express: `/health` against a dead backend, and
  three calibration runs.
- `golden.json` — the recorded reference behaviour: 47 cases. This is the
  contract the Pascal port has to meet.
- `transforms.pas` / `transforms.build.sh` / `transforms_check.py` — the
  differential harness for `src/proxycore.pas`. `transforms.pas` reads a JSON
  array of jobs on stdin and writes one result per job; `transforms_check.py`
  builds the corpus, computes the expected answers by calling the Python
  functions directly, and compares. Extending it costs one entry in a list --
  nobody has to work out by hand what the answer should be. The corpus
  carries no NUL bytes: cJSON returns strings as NUL-terminated C strings, so
  a JSON value containing one truncates there. `PxUtf8Valid` and `PxCharLen`
  are checked by `tests/integration/proxycore_unit.pas` instead, since a
  corpus that travels as JSON can only carry text that is already valid
  UTF-8.
- `corpus/` — 64 realistic `/complete` payloads. 56 were cut from real,
  known-compiling programs under `tests/golden`, `tests/integration` and a
  sibling project-euler checkout at a clean line boundary, so each one's
  `buffer` plus its `reference_continuation` is that program again; the other
  8 are hand-written micro-cases and whole-task prompts. Buffers run from
  empty to 3875 characters. `build_corpus.py` regenerates the derived items;
  the hand-written ones have no source to derive from and are committed as
  they are.
- `test_corpus.py` — unit tests for `build_corpus.py`'s split-point logic and
  a shape check over every committed item. The reconstruction test is the one
  that matters: it is what keeps `corpus_smoke.py --reference` meaningful,
  since that mode relies on buffer + recorded continuation being the original
  program byte for byte.
- `corpus_smoke.py` — replays that corpus. Against a live backend it also
  appends each completion to its buffer and compiles the result with the real
  compiler, which is an objective quality signal no stub can produce.
  `--reference` skips the proxy and the model entirely and compiles each
  item's own recorded continuation, which checks the corpus against the
  compiler and the compile check against itself.
- `oneshot.pas` / `oneshot.build.sh` / `oneshot.sh` / `oneshot.expected` — one
  upstream call written in the vintage dialect, the step-5 milestone of the
  port. It is not the proxy: no calibration, no echo stripping, no server
  side. What it pins is that a payload built with `jsonx`, sent over `netsock`
  through `httpio`, is one a real backend accepts, and that every reply shape
  — string content, content as parts, an exhausted reasoning budget, an empty
  `choices`, a 500, unparseable JSON — is told apart rather than collapsing
  into one unhelpful failure. Point `--base-url` at a live backend to run the
  same thing against a real model.

## What is deliberately not compared

The `Server` and `Date` headers, the HTTP version, and the reason phrase: each
is free for an implementation to choose and no client depends on any of them.
The stub's port number is masked, and the OS error text for a refused
connection is normalized — that `/health` answers 503 is the contract, the
wording of `errno` is not.
