# pascal1981-mode

`pascal1981-mode` is a major mode for the 1981 IBM Pascal dialect.
This compiler implements that dialect.

The mode does not implement the language again. The mode sends the
buffer text to the stage binaries `lexer` and `parser`. Then the
mode uses the JSON that those binaries write.

## Requirements

Put the Native Pascal 1981 binaries on `PATH`. The mode looks for
the names `lexer` and `parser`. You can set other names:

```elisp
(setq pascal1981-lexer-program "lexer")
(setq pascal1981-parser-program "parser")
```

## Load the mode

There is no install target. Add the `elisp/` directory to
`load-path`. Then load the feature:

```elisp
(add-to-list 'load-path "/path/to/native-pascal-1981/elisp")
(require 'pascal1981-mode)
```

Emacs uses `pascal1981-mode` for `.pas` and `.inc` buffers. The
`.inc` suffix is the include file of this dialect. An include file
is often not a complete compilation unit. Font lock and indent still
work. `pascal1981-check-buffer` and imenu can fail on that file.

## What the mode does

| Feature | Source |
| --- | --- |
| Font lock after idle time | Token stream from `lexer` |
| Font lock fallback | Elisp keywords, if the lexer is not available |
| Indentation | Token kinds such as `BEGIN`, `END`, `THEN`, and `DO`. `TAB` and `indent-region` both use this |
| Imenu | Parser AST decls, mapped to token positions in declaration order |
| `M-x pascal1981-refresh` | Re-run `lexer` and `parser` on the buffer. Then apply faces |
| `M-x pascal1981-check-buffer` | `lexer \| parser`. Shows parser stderr, or `No parser errors` |
| Flycheck | Optional. The mode registers a checker only if flycheck is loaded |

The idle delay is `pascal1981-idle-delay` (0.4 s by default).
The indent width is `pascal1981-indent-width` (2 by default).

`C-M-\\` (`indent-region`) indents each line in the region. The mode
sets `indent-line-function` to `pascal1981-indent-line`. Emacs then
calls that function once per line.

Indent uses the lexer token stream. The parser AST has no source
spans, and the parser fails on half-typed buffers. `BEGIN`, `RECORD`,
and `REPEAT` open a block. `CASE ... OF` opens a block. `THEN`, `DO`,
and `ELSE` indent the next line only when they end that line. `SET OF`
and `ARRAY OF` do not indent. Names after `VAR`, `CONST`, or `TYPE`
align to the first identifier of that section. If `VAR` is alone on a
line, the next name indents by one width.

Imenu lists one entry for each declared name. `VAR X, YY: INTEGER;`
is one `VarDecl` with two names, and each name gets its own entry.

A name resolves to a token by a left to right scan of the token
stream. A cursor moves past each declaration, so a name declared late
does not resolve to an earlier record field or parameter that shares
the lexeme. The AST has no source spans, so this order is the only
scope the mode has. The index covers the top-level block only, so a
name declared in a nested body can still shadow.

## Tests

Run the ERT suite with make, from any directory:

```sh
make -C elisp test
```

The target puts `bin/` on `PATH` for you. It fails first if `lexer`
or `parser` is not built, because most tests carry `skip-unless` and
report success when the binaries are absent.

The top-level `make test` does not run this target. The compiler does
not need Emacs.

To run ERT directly, put `bin/` on `PATH` and run from the repo root:

```sh
PATH="$PWD/bin:$PATH" emacs -Q --batch -L elisp \
  -l elisp/pascal1981-mode-tests.el \
  -f ert-run-tests-batch-and-exit
```

## LLM code completion (optional)

`pascal1981-mode` can offer TAB-triggered code completion from a local LLM,
through a small HTTP proxy in `tools/pascal1981_completion_proxy.py`. This
is off by default and entirely optional.

**Emacs never starts, stops, or supervises the proxy.** You run it yourself,
outside of Emacs, before you enable completion:

```sh
python3 tools/pascal1981_completion_proxy.py
```

By default it listens on `127.0.0.1:8790` and talks to an
OpenAI-completions-compatible backend at `http://127.0.0.1:8080/v1` — i.e.
localhost, port 8080, a local `llama.cpp` server. Configuration is by CLI
flag (`--help` lists them all); point it at a different backend with
`--llm-base-url`:

```sh
python3 tools/pascal1981_completion_proxy.py --llm-base-url http://192.0.2.10:8080/v1
```

The one setting that stays an environment variable, `LLM_API_KEY`, is the
deliberate exception: a secret doesn't belong on a command line, which any
other process on the machine can read via `ps`, and which shells commonly
save to history. Most local `llama.cpp`/LM Studio setups need no key at
all.

Optionally pass `--grammar-file docs/ebnf_grammar.md` to give the model the
dialect's EBNF grammar as reference context. This was tested and found not
to help completion quality while costing prompt size and latency; it stays
available (off by default) in case a future prompt shape changes that, not
because it's currently recommended.

The prompt wording sent to the model lives in `tools/prompts/system_prompt.txt`
(a plain text file, not a string literal in the proxy), so it can be read
and tuned without touching code. Override it with `--system-prompt-file`
without editing the bundled file. The bundled prompt is deliberately
minimal — a full-corpus experiment found that an elaborate, heavily
instructed prompt was itself the dominant cause of a failure mode where the
model echoed text already before the cursor instead of continuing past it;
stripping the prompt down to almost nothing eliminated that failure
entirely (0/64 occurrences across two different backends, vs. 22-30% under
the old wording). Resist the urge to add guardrail language back in without
re-measuring its effect.

If the proxy isn't running, or you haven't started it yet, completion
requests just fail — TAB falls back to ordinary indentation. There is no
auto-start path; Emacs is only ever an HTTP client to whatever is already
listening at `pascal1981-completion-proxy-url`.

### Enabling it in Emacs

```elisp
(setq pascal1981-completion-enabled t)
;; Optional, only if you changed the proxy's host/port:
;; (setq pascal1981-completion-proxy-url "http://127.0.0.1:8790/complete")
```

Or interactively, `M-x pascal1981-completion-toggle` — a plain toggle,
flipping `pascal1981-completion-enabled` on or off.

Other knobs: `pascal1981-completion-goal` (the instruction sent with every
request), `pascal1981-completion-timeout` (seconds to wait before giving
up, default 8), `pascal1981-completion-buffer-limit` (nothing larger than
this, in characters, is ever sent — see "Large files" below for what
actually gets measured against it).

Each request makes exactly one upstream call and gets back exactly one
completion — there is no multi-candidate ("give me N different
completions") support. This was tried (packing several distinct
completions into one JSON response, since backend-level `"n"` sampling
turned out not reliably usable across backends — one silently ignores it
and returns a single choice regardless, another hard-rejects any value
other than 1) and later dropped: browsing one generous completion's lines
with `M-n`/`M-p` (below) serves the same "give me more to look at" need
without the complexity, and without ever requiring more than one API call
per request.

### Browsing a multi-line completion: line reveal with M-n/M-p

Completions are no longer capped at one line by default (see the proxy's
`--max-lines` flag, default 30) — a completion can be several lines. Only
the first line is shown in the ghost-text preview at first, though:
`M-n`/`M-p` reveal more or fewer of the completion's lines, one Fibonacci
step at a time (1, 2, 3, 5, 8, 13, ... lines — the raw Fibonacci sequence's
repeated leading 1, 1 collapsed to a single step, since two consecutive
`M-n` presses revealing the same line count would do nothing). The preview
shows a `[i/N lines]` suffix whenever the completion is more than one line
long. `M-n` stops at the full completion rather than wrapping back to one
line; `M-p` stops at one line rather than wrapping to the full completion.

Accepting with TAB inserts only the lines currently revealed, not
necessarily the whole completion — what you see in the preview is what
gets inserted. A multi-line accept re-indents the inserted lines against
the buffer's normal indentation rules (see `pascal1981--completion-insert`),
since the raw model text carries no indentation of its own.

### Large files: sending a lexical unit instead of the whole buffer

A request normally sends the whole buffer. Once the buffer exceeds
`pascal1981-completion-lexical-unit-threshold` (characters, default 4000),
the mode instead sends only the innermost enclosing `PROCEDURE`/`FUNCTION`
around point, plus the top-level declarations (the `PROGRAM` header and any
top-level `CONST`/`TYPE`/`VAR`/`LABEL` section) — not the whole file. This
is what actually lets completion work on a file far larger than
`pascal1981-completion-buffer-limit` would otherwise allow: only the
relevant lexical unit has to fit that limit, not the entire file.

The top-level declarations are always included alongside the unit, not
just the unit alone — dropping them was found, during this feature's
design, to measurably hurt completion correctness on at least one backend
(it started fabricating unrelated logic once it lost sight of what a
variable was declared as). Cursor position is translated to be relative to
the sent slice; the proxy never needs to know a slice happened.

If point is not inside any `PROCEDURE`/`FUNCTION` — e.g. it's in the
top-level declarations or the main `BEGIN...END` block — there is no unit
to slice to, and the whole buffer is sent regardless of size, same as
before this feature existed. A crude "some lines around point" fallback
was considered for that case and rejected: it seemed more likely to
produce a confusing or syntactically broken excerpt than a clean
procedure-boundary slice reliably does.

Set `pascal1981-completion-lexical-unit-threshold` very high to disable
slicing entirely and always send the whole buffer (subject to
`pascal1981-completion-buffer-limit` as before).

### TAB behavior

Completions show as a dismissible ghost-text preview, not an immediate
insert — you always see what would be inserted before it lands.

TAB (`pascal1981-indent-or-complete`, remapped from
`indent-for-tab-command`) does one of three things:

- **A preview is already showing at point.** TAB accepts it: the shown
  candidate is inserted as a single atomic undo step, and the preview goes
  away.
- **No preview, and point is eligible.** Completion must be enabled, point
  must sit before nothing but whitespace on the current line
  (`(looking-at-p "[ \t]*$")`), and whatever would actually be sent (the
  whole buffer, or a lexical-unit slice of it — see "Large files" above)
  must not exceed `pascal1981-completion-buffer-limit`. TAB requests a
  completion; when the (asynchronous) response arrives, it renders as a
  ghost-text preview rather than inserting immediately.
- **Anything else** — completion disabled, mid-line, oversized buffer — TAB
  keeps its ordinary meaning: `pascal1981-indent-line`. This fallback is
  always exactly indentation, never a no-op, so disabling or losing the
  proxy never costs TAB its normal behavior.

`M-x pascal1981-complete-line` requests a completion directly, using the
same eligibility rule as the second case above.

While a preview is showing:

- **`M-n` / `M-p`** reveal more/fewer of the completion's lines (see
  "Browsing a multi-line completion" above; only meaningful for a
  completion longer than one line).
- **Any other command** — typing a character, moving point, `C-g`,
  switching buffers — dismisses the preview without inserting anything.

A response only ever turns into a preview if the buffer is still
unchanged, point hasn't moved, and the eligibility rule still holds at the
point the (asynchronous) response arrives — a response that arrives after
you've kept typing is discarded rather than shown somewhere it no longer
applies.

### Manually checking the proxy

```sh
curl http://127.0.0.1:8790/health
```

This makes one real call to the configured LLM backend (not just a socket
check) and reports the model, the resolved `reasoning_effort` setting, and
a sample completion. Useful for confirming the LLM itself is actually
responding before troubleshooting from inside Emacs.

### Troubleshooting

- **TAB just indents, no completion happens.** Either
  `pascal1981-completion-enabled` is nil, point isn't at end-of-line-modulo-
  whitespace, or what would be sent is over `pascal1981-completion-buffer-limit`
  even after lexical-unit slicing — and no preview was already showing at
  point, which is the only other
  thing TAB can do instead of indenting. This is by design, not a failure —
  check `pascal1981-complete-line` directly (`M-x`) to isolate eligibility
  from a proxy problem.
- **The preview disappeared before I could accept it.** Any command other
  than TAB (to accept) or `M-n`/`M-p` (to reveal more/fewer lines)
  dismisses the preview —
  including typing, moving point, and `C-g`. This is intentional: a stale
  preview left showing after you kept typing would no longer apply to what's
  at point.
- **"pascal1981: completion request failed: (error connection-refused ...)"**
  The proxy isn't running, or `pascal1981-completion-proxy-url` points at
  the wrong host/port. Start the proxy yourself (see above); Emacs will not
  do it for you.
- **"pascal1981: completion request timed out"** The proxy is up but the
  backend didn't answer within `pascal1981-completion-timeout` seconds. Try
  `curl .../health` directly — a reasoning model that needs a larger
  `--max-tokens`, or a wrong `--reasoning-effort` left over from a previous
  model at the same endpoint, are the usual causes. The proxy self-
  calibrates `reasoning_effort` at startup when `--reasoning-effort` isn't
  passed explicitly, but that calibration only runs once, at proxy
  startup — if you swap the model loaded at the backend without restarting
  the proxy, the old calibration can go stale and start failing. Restart
  the proxy after swapping models.
- **"pascal1981: completion proxy returned HTTP 5xx"** / **"...response was
  empty or malformed"** The proxy reached the backend but couldn't get a
  usable answer out of it (see the proxy's own stderr for detail).

### Privacy

Enabling completion sends the buffer's full text (or, on a large buffer, a
lexical-unit slice of it — see "Large files" above), plus the cursor
position and (if configured) the EBNF grammar, to whatever backend
`pascal1981-completion-proxy-url` currently points at through the local
proxy. For a local backend nothing leaves your machine; for anything else,
that's on you to configure knowingly.

## I/O contract

The `lexer` binary reads Pascal source on stdin. It writes a JSON
token array on stdout. It exits with status 0.

The `parser` binary reads that JSON array on stdin. It writes a
JSON AST on stdout. On success it exits with status 0. On failure
it exits with status 1 and writes `Parser Error: ...` on stderr.

CAUTION: Do not send `[]` to the parser. The parser can crash.

Each token object has these fields: `kind`, `code`, `lexeme`,
`value`, `line`, `column`, and `flags`. Each AST object has a
`__node_type__` field.
