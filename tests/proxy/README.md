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
