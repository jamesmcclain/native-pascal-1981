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

## What is deliberately not compared

The `Server` and `Date` headers, the HTTP version, and the reason phrase: each
is free for an implementation to choose and no client depends on any of them.
The stub's port number is masked, and the OS error text for a refused
connection is normalized — that `/health` answers 503 is the contract, the
wording of `errno` is not.
