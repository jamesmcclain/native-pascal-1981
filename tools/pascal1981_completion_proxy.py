#!/usr/bin/env python3
"""Local HTTP proxy: pascal1981-mode <-> an OpenAI-completions-compatible API.

Emacs never starts this process. A person starts it by hand (see
elisp/README.md) and it keeps running until they stop it; the mode is only
ever an HTTP client of whatever is already listening on --host:--port.

Protocol (see pascal-completion-plan.md):

    POST /complete
    {"goal": "...", "buffer": "...", "cursor": {"line": N, "column": N}}
    ->
    {"completions": ["..."], "model": "...", "request_id": "..."}

"completions" is always a single-element list. There is deliberately no
"n" / multi-candidate support: it was tried (a prompt asking the model for
a JSON object of several completions in one request, since backend-level
"n" is not reliably usable -- LM Studio silently ignores it, llama.cpp
hard-rejects any value other than 1 with an HTTP 400) and later shelved --
every request makes exactly one upstream call, full stop, and the Emacs
client instead reveals more of one generous completion via M-n/M-p rather
than cycling between several distinct ones. See autoresearch notes below
for why.

Configuration is by CLI flag (run --help for the full list), not
environment variables -- the one exception is LLM_API_KEY, which stays
environment-only because a secret does not belong on a command line
visible to every other process on the machine (`ps`) or preserved in
shell history. By default the upstream backend is
http://127.0.0.1:8080/v1 (a local llama.cpp server on localhost, port
8080), reached through its OpenAI-compatible /chat/completions endpoint;
override with --llm-base-url. LLM_API_KEY is optional; llama.cpp needs
none. Only stdlib is used -- no extra dependency to install before the
proxy can start.

Why /chat/completions and not the legacy /completions endpoint: verified
live against a real backend (a reasoning-tuned model served by llama.cpp)
that the raw /completions endpoint leaks fragments of the model's internal
Harmony-format chain-of-thought into the completion text (e.g. a bare
"thought", or "<|channel|>..." markers) instead of Pascal. Sending
"reasoning_effort": "none" -- a top-level field, not nested under
chat_template_kwargs -- on /chat/completions eliminates that: it makes the
model skip its hidden reasoning pass entirely and answer directly. A backend
that does not understand the field is expected to ignore it, per the usual
"unknown JSON field" tolerance of OpenAI-compatible servers; if one does not,
--reasoning-effort can be set to an empty string to omit it.

Porting notes (for a future native pascal1981 port of this proxy):

- Every buffer/JSON payload here (the request body, the source-buffer
  prefix, upstream request/response bodies) can exceed 255 characters --
  the dialect's LSTRING(n) stores its length as a single byte (0..255), so
  none of this data can be carried in an LSTRING. It has to be a raw
  ADRMEM/^CHAR buffer with an explicit INTEGER32 length, the same pattern
  src/jsonutil.pas's ReadAllStdin/MakeCStr/CStrToStr255 already use for
  arbitrary-length C-string data.
- Every CLI flag below is used, in practice, only as `--flag value`
  (long form, space-separated). There is no `--flag=value` usage, no
  abbreviated/prefix matching, and no combined short flags anywhere this
  proxy is invoked -- a hand-rolled Pascal argv parser only needs to
  implement that one, narrow grammar, not argparse's full feature set.

Autoresearch notes (for an effort that optimizes completion quality by
varying prompts and proxy parameters, without touching this file):

- The tunable surface is not just tools/prompts/system_prompt.txt.
  --temperature, --reasoning-effort, --max-tokens, and --grammar-file are
  all real, high-impact levers on quality that live in CLI flags / Config,
  not prompt text -- include them in the search space, not just prompt
  wording.
- A full-corpus experiment (see /home/ubuntu/autoresearch_notes.md,
  "Headline finding: a minimal prompt (no proxy) eliminates the echo bug")
  found that a near-bare system prompt eliminates the dominant "echo bug"
  failure mode (the model retyping text already before the cursor): 0/64
  echoes at full-corpus scale on two different backends, vs. 22-30% under
  a more elaborate, heavily-instructed prompt this file used to ship. That
  finding is what SYSTEM_PROMPT now is -- verbatim, not adapted or
  extended, per explicit instruction not to ship any wording beyond what
  was actually measured. Multi-candidate support (a prompt asking for
  several completions packed into one JSON response) was tried and later
  shelved entirely, for two reasons: the backend's one-connection-at-a-time
  behavior and the Emacs client's completion timeout ruled out ever making
  more than one upstream call per request, and once the client started
  revealing more of a single generous completion via M-n/M-p instead of
  cycling between candidates, packing multiple *distinct* completions into
  one response stopped solving a problem that still existed. On the elisp
  side, M-n/M-p now step through a single completion's lines at
  deduplicated Fibonacci-spaced counts (1, 2, 3, 5, 8, 13, ... -- not the
  raw Fibonacci sequence's repeated leading 1, 1, since two consecutive
  keystrokes revealing the same line count would be a no-op).
- `strip_echo` is unconditional, mechanical defense-in-depth against the
  echo bug, run on every completion in `do_POST` regardless of how rare
  it now is under the minimal prompt: the 0/64 result above was measured
  against one 64-item corpus, not proven impossible in general. It is a
  literal, character-level overlap check between the buffer's tail and
  the candidate's start, only stripped once the match exceeds
  `_ECHO_MIN_OVERLAP` characters. An earlier word-level, case/whitespace-
  normalized version of this function looked safer on paper but was not:
  it silently ate real completions whenever a *short* repeated word was
  legitimate rather than an echo -- e.g. two nested blocks correctly
  closing back-to-back both end in "END;", and that got stripped down to
  nothing, live in Emacs. A short overlap is common, structurally
  required repetition; only a longer one is implausible as coincidence.
- --grammar-file was independently tested and found not to help completion
  quality while inflating prompt size and upstream latency -- it remains
  available (off by default) in case a future prompt shape changes that
  finding, but treat it as a known-not-helpful lever, not a live one.
- Swapping --llm-base-url or the model loaded behind an existing one
  without restarting the proxy leaves --reasoning-effort=auto's
  calibration stale (see calibrate_reasoning_effort) -- restart the proxy
  on every backend/model change in an experiment sweep, don't just
  repoint the flag.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
import socketserver
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

# --------------------------------------------------------------------------
# Prompt text (side-car files, not hardcoded in this module)
# --------------------------------------------------------------------------

_PROMPTS_DIR = Path(__file__).resolve().parent / 'prompts'


def load_prompt_text(filename: str) -> str:
    """Read a prompt template from tools/prompts/FILENAME.

    Prompt wording lives in these side-car files, not as string literals
    in this module, so it can be read and tuned without touching code --
    the same reasoning as `--grammar-file` for the (much larger) EBNF
    reference text. A single trailing newline (most editors add one on
    save) is stripped; it is not part of the prompt.
    """
    return (_PROMPTS_DIR / filename).read_text(encoding='utf-8').rstrip('\n')


def load_prompt_override(path: str) -> str:
    """Read a --system-prompt-file override from an arbitrary PATH (unlike
    `load_prompt_text`, not relative to the bundled tools/prompts/
    directory). Raise OSError on failure -- a bad override path should
    fail the proxy at startup, not silently fall back to the bundled
    default."""
    with open(path, encoding='utf-8') as handle:
        return handle.read().rstrip('\n')

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------


def load_grammar(path: str) -> str:
    """Read the grammar reference file at PATH. Raise OSError on failure --
    a bad --grammar-file should fail the proxy at startup, not silently
    drop grammar context on every request."""
    with open(path, encoding='utf-8') as handle:
        return handle.read()


class Config:
    """Proxy configuration. Built from parsed CLI flags (see `parse_args`)
    at startup; every field has a keyword-argument default here too, so
    tests and other callers can construct one directly without going
    through argv.

    LLM_API_KEY is the one setting still read from the environment rather
    than taken as a constructor argument (unless a caller passes
    llm_api_key explicitly): a secret does not belong on a command line,
    which any other process on the machine can read via `ps`, and which
    shells commonly persist to history. Every other setting has no such
    motivation to avoid a CLI flag, so it is one.
    """

    def __init__(self,
                 host: str = '127.0.0.1',
                 port: int = 8790,
                 llm_base_url: str = 'http://127.0.0.1:8080/v1',
                 llm_api_key: str | None = None,
                 llm_model: str = 'default',
                 buffer_limit: int = 65536,
                 # 512, not the ~32 a non-reasoning backend would need:
                 # observed live, a reasoning model can spend 200-360+
                 # tokens in reasoning_content before ever writing an
                 # answer, even with reasoning_effort tuned to the value
                 # that lets it actually finish -- and that cost rises
                 # further with a larger prompt (e.g. --grammar-file's
                 # ~2300 extra prompt tokens pushed one case from ~200 to
                 # 359 reasoning tokens in testing). A tighter budget for a
                 # backend that never reasons just means the request
                 # finishes early once its answer is written; it does not
                 # cost extra latency there, so the larger default is safe
                 # for both kinds of backend, not just a concession to one
                 # of them.
                 max_tokens: int = 512,
                 temperature: float = 0.2,
                 # 20s, not the 5-10s a non-reasoning backend would need: a
                 # reasoning-heavy completion at ~90 tokens/s can take
                 # several seconds even before writing an answer.
                 #
                 # This value is paired with `pascal1981-completion-timeout`
                 # in elisp/pascal1981-mode.el, which must not be shorter.
                 # It used to be: the client gave up at 8s while this budget
                 # ran to 20s, so every slow request died client-side with a
                 # blind "timed out" -- the user never saw the proxy's own
                 # diagnosis, and the forked child went on holding the
                 # upstream call open after the client had walked away. The
                 # two now match at 20s, with the client adding a small
                 # transport grace on top so this side always answers first.
                 # Change one and change the other.
                 upstream_timeout: float = 20.0,
                 # Sent as a top-level "reasoning_effort" field on every
                 # request to /chat/completions. Set to an empty string to
                 # omit the field entirely, for a backend that rejects
                 # unknown fields outright.
                 #
                 # The default is the literal sentinel "auto": observed
                 # live, the *wrong* value here does not just fail to
                 # help, it actively breaks a model that would otherwise
                 # work fine (a reasoning model given the wrong effort
                 # level burns its whole token budget without ever
                 # answering, and a non-reasoning model given a value
                 # meant for a different, reasoning-heavy model can do the
                 # same). Since the correct value is a property of
                 # whichever model happens to be loaded right now, not of
                 # the proxy, "auto" tells main() to run
                 # calibrate_reasoning_effort() against the live backend
                 # at startup and resolve this field before serving.
                 # Setting --reasoning-effort explicitly (to "none",
                 # "low", "medium", "high", or "") always skips
                 # calibration and is used as-is -- an operator's explicit
                 # choice is never second-guessed.
                 reasoning_effort: str = 'auto',
                 # Optional: prepend the dialect's EBNF grammar to every
                 # prompt as reference context. Off by default -- it costs
                 # prompt tokens and upstream latency on every
                 # eligible-TAB request, so it is opt-in via
                 # --grammar-file, not auto-detected from
                 # docs/ebnf_grammar.md even though that file is a natural
                 # fit.
                 grammar_file: str = '',
                 # Defaults to the bundled tools/prompts/system_prompt.txt
                 # (see `load_prompt_text`) when left as None. Overridable
                 # via --system-prompt-file so prompt wording can be tuned
                 # per deployment without touching this module -- the same
                 # reasoning as --grammar-file.
                 system_prompt: str | None = None,
                 # Safety-valve cap on completion length, in lines -- not a
                 # quality lever. Deliberately generous (see
                 # `sanitize_completion`'s docstring for why 1, the old
                 # default, is wrong): a completion running longer than a
                 # real single-statement or short-block continuation is
                 # welcome, not a bug to prevent, per the "too much
                 # completion is better than too little; extra can be
                 # stripped in some appropriate way" guidance that drove
                 # this default's increase from 1 to 30.
                 max_lines: int = 30) -> None:
        self.host = host
        self.port = port
        self.llm_base_url = llm_base_url.rstrip('/')
        self.llm_api_key = (llm_api_key if llm_api_key is not None else
                             os.environ.get('LLM_API_KEY', ''))
        self.llm_model = llm_model
        self.buffer_limit = buffer_limit
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.upstream_timeout = upstream_timeout
        self.reasoning_effort = reasoning_effort
        self.grammar_file = grammar_file
        self.grammar_text = (load_grammar(self.grammar_file)
                              if self.grammar_file else '')
        self.system_prompt = (system_prompt
                              if system_prompt is not None else SYSTEM_PROMPT)
        self.max_lines = max_lines

    @property
    def chat_completions_url(self) -> str:
        return f'{self.llm_base_url}/chat/completions'


# --------------------------------------------------------------------------
# Request validation
# --------------------------------------------------------------------------


class RequestError(Exception):
    """Malformed /complete request. Message is safe to return to the client."""


def validate_request(
        payload: object,
        buffer_limit: int) -> tuple[str, str, int, int]:
    """Validate a decoded /complete JSON body.

    Return (goal, buffer, line, column) on success. Raise RequestError with
    a client-safe message otherwise.
    """
    if not isinstance(payload, dict):
        raise RequestError('request body must be a JSON object')

    buffer = payload.get('buffer')
    if not isinstance(buffer, str):
        raise RequestError('"buffer" must be a string')
    if len(buffer) > buffer_limit:
        raise RequestError(
            f'"buffer" exceeds the {buffer_limit}-character limit')

    goal = payload.get('goal', '')
    if not isinstance(goal, str):
        raise RequestError('"goal" must be a string')

    cursor = payload.get('cursor')
    if not isinstance(cursor, dict):
        raise RequestError('"cursor" must be an object with line/column')
    line = cursor.get('line')
    column = cursor.get('column')
    if not isinstance(line, int) or isinstance(line, bool) or line < 1:
        raise RequestError('"cursor.line" must be a positive integer')
    if not isinstance(column, int) or isinstance(column, bool) or column < 1:
        raise RequestError('"cursor.column" must be a positive integer')

    return goal, buffer, line, column


def compute_prefix(buffer: str, line: int, column: int) -> str:
    """Text from the start of BUFFER through the 1-indexed LINE/COLUMN point.

    Mirrors pascal1981--line-col-pos in elisp/pascal1981-mode.el: COLUMN
    counts characters (a tab is one column), and both LINE and COLUMN are
    clamped to the buffer's actual extent rather than erroring, since a
    stale cursor position is a race, not a client bug.
    """
    lines = buffer.split('\n')
    line_index = min(max(line, 1), len(lines)) - 1
    target_line = lines[line_index] if lines else ''
    col_index = min(max(column, 1) - 1, len(target_line))
    prefix_lines = lines[:line_index] + [target_line[:col_index]]
    return '\n'.join(prefix_lines)


_GRAMMAR_HEADER = '# --- Pascal 1981 EBNF grammar reference (context only, do not repeat) ---'
_GRAMMAR_FOOTER = '# --- end grammar reference ---'


def build_prompt(goal: str,
                 prefix: str,
                 grammar: str = '') -> str:
    """Build the user-message content sent upstream (see SYSTEM_PROMPT for
    the accompanying system message).

    The content is mostly the literal source prefix, formatted so the model
    sees it as "the code so far" to continue -- that reads naturally
    alongside SYSTEM_PROMPT's instruction to complete at the end of it. A
    non-empty GOAL is carried as a one-line Pascal comment immediately
    before the prefix, kept off its own line's indentation so it cannot be
    mistaken for buffer content.

    A non-empty GRAMMAR (the dialect's EBNF reference, opt-in via
    --grammar-file) is prepended ahead of everything else, marked with a
    plain '#' header/footer rather than a Pascal '{ }' or '(* *)' comment:
    the grammar text itself contains both of those delimiter pairs (as EBNF
    repetition syntax and as worked examples), so wrapping it in either
    would let its own content close the wrapper early.
    """
    goal = goal.strip().replace('\n', ' ')
    body = f'{{ {goal} }}\n{prefix}' if goal else prefix
    if not grammar.strip():
        return body
    return f'{_GRAMMAR_HEADER}\n{grammar.strip()}\n{_GRAMMAR_FOOTER}\n\n{body}'


# --------------------------------------------------------------------------
# Upstream call
# --------------------------------------------------------------------------


class UpstreamError(Exception):
    """Upstream call failed. Message is safe to return to the client (no
    upstream body / credentials leaked)."""


class ReasoningBudgetExhausted(UpstreamError):
    """The model spent its whole token budget on hidden reasoning and never
    answered. A specific subtype (not just UpstreamError) because
    `calibrate_reasoning_effort` needs to distinguish this ("this
    reasoning_effort value is wrong for this model, try the next one") from
    every other UpstreamError ("the backend is unreachable/broken, stop
    calibrating and fall back immediately -- trying four more candidates
    against a dead backend just multiplies the timeout wait for no
    benefit")."""


SYSTEM_PROMPT = load_prompt_text('system_prompt.txt')


def call_upstream(prompt: str,
                   config: Config,
                   max_tokens: int | None = None,
                   temperature: float | None = None,
                   reasoning_effort: str | None = None,
                   system_prompt: str | None = None) -> dict:
    """POST PROMPT (the user-message content from `build_prompt`) to the
    configured /chat/completions endpoint, alongside a system message.
    Return the parsed JSON response. Raise UpstreamError on any transport,
    timeout, HTTP, or JSON failure.

    MAX_TOKENS / TEMPERATURE / REASONING_EFFORT default to CONFIG's values;
    callers that want to probe a value without touching the configured
    completion behavior (see `ping_upstream`, `calibrate_reasoning_effort`)
    can override them. REASONING_EFFORT follows CONFIG.reasoning_effort's
    convention: '' omits the field, and the sentinel 'auto' is never valid
    here -- calibrate_reasoning_effort is what resolves 'auto' into a real
    value or '', so if it somehow still reaches this function it is treated
    the same as '' (omit) rather than sent upstream literally. SYSTEM_PROMPT
    defaults to the module-level `SYSTEM_PROMPT` constant when omitted.
    There is deliberately no "n" field sent upstream, and no multi-candidate
    support at all: verified live, one backend (LM Studio) silently ignores
    "n" and returns a single choice, and another (llama.cpp) hard-rejects
    any "n" other than 1 with an HTTP 400 -- and packing several candidates
    into one JSON response (this proxy's earlier approach) was tried and
    later shelved (see the module docstring's autoresearch notes). Every
    request now makes exactly one call and returns exactly one completion.

    Porting note: PAYLOAD below never sets "stream": true, so every upstream
    response is a single complete JSON body delimited by a normal
    Content-Length header -- never chunked transfer-encoding, never SSE
    framing. A future socket-based Pascal HTTP client only has to read
    exactly Content-Length bytes after the header block; it never needs to
    handle a chunked or streamed response from this code path.
    """
    payload = {
        'model':
            config.llm_model,
        'messages': [
            {
                'role': 'system',
                'content': system_prompt if system_prompt is not None else
                SYSTEM_PROMPT
            },
            {
                'role': 'user',
                'content': prompt
            },
        ],
        'max_tokens':
            config.max_tokens if max_tokens is None else max_tokens,
        'temperature':
            config.temperature if temperature is None else temperature,
    }
    # Deliberately no "stop": ["\n"] here. Observed live: at least one
    # backend applies `stop` to the raw underlying token stream, which
    # includes a reasoning model's `reasoning_content` -- and reasoning text
    # routinely contains newlines. A global "\n" stop then kills generation
    # while the model is still thinking, before it ever reaches the answer
    # channel, so the request "succeeds" with permanently empty content no
    # matter how large max_tokens is. Single-line enforcement is already the
    # client's job: `sanitize_completion` truncates the *returned content*
    # (not the raw stream) at its first newline, which is safe regardless of
    # whether the backend reasons at all.
    effective_reasoning_effort = (config.reasoning_effort
                                   if reasoning_effort is None else
                                   reasoning_effort)
    if effective_reasoning_effort and effective_reasoning_effort != 'auto':
        payload['reasoning_effort'] = effective_reasoning_effort
    body = json.dumps(payload).encode('utf-8')

    headers = {'Content-Type': 'application/json'}
    if config.llm_api_key:
        headers['Authorization'] = f'Bearer {config.llm_api_key}'

    request = urllib.request.Request(config.chat_completions_url,
                                      data=body,
                                      headers=headers,
                                      method='POST')
    try:
        with urllib.request.urlopen(
                request, timeout=config.upstream_timeout) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        raise UpstreamError(
            f'upstream returned HTTP {exc.code}') from exc
    except urllib.error.URLError as exc:
        raise UpstreamError(f'could not reach upstream: {exc.reason}') from exc
    except TimeoutError as exc:
        raise UpstreamError('upstream request timed out') from exc

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise UpstreamError('upstream returned malformed JSON') from exc


# Used by both ping_upstream and calibrate_reasoning_effort. Observed live: a
# generic one-line probe sentence gives a false "it works" signal -- a
# reasoning model can answer a trivial sentence directly while still
# reliably exhausting its budget on an actual Pascal-completion prompt of
# the shape /complete really sends. This is the empirically hardest of the
# three cases exercised during development (a FOR-loop header needing a
# multi-token, syntax-aware completion), not an arbitrary choice.
_PROBE_BUFFER = 'PROGRAM Demo;\nVAR i: INTEGER;\nBEGIN\n  FOR i := 1 \nEND.\n'
_PROBE_LINE = 4
_PROBE_COLUMN = 14


def _probe_prompt(config: Config) -> str:
    """Build a /complete-shaped prompt for probing the backend, including
    CONFIG.grammar_text -- --grammar-file materially changes prompt size and
    therefore reasoning cost, so a probe that ignores it is not
    representative of what real requests will actually send."""
    prefix = compute_prefix(_PROBE_BUFFER, _PROBE_LINE, _PROBE_COLUMN)
    return build_prompt('', prefix, config.grammar_text)


def ping_upstream(config: Config) -> tuple[str, str]:
    """Make one real call to the upstream backend, using the same
    representative probe prompt as `calibrate_reasoning_effort`, to confirm
    it is actually generating text for realistic requests -- not just that
    its port accepts connections, and not just that it can answer something
    trivial.

    Returns (completion_text, model). Raises UpstreamError exactly like
    `call_upstream` -- callers (the /health route, or a person invoking this
    module with --ping) treat that as "not responding".

    Deliberately reuses CONFIG.max_tokens rather than a small fixed budget: a
    tiny probe budget (e.g. 4 tokens) reliably reports "not responding" on a
    reasoning backend that needs its full configured budget just to finish
    thinking, even though a real /complete request at that same budget would
    succeed. The probe is only as cheap as a real request is -- that is the
    honest question to answer ("will my configured requests work"), not
    "does the socket respond."
    """
    response = call_upstream(_probe_prompt(config),
                             config,
                             temperature=0.0,
                             system_prompt=config.system_prompt)
    text, model, _request_id = extract_completions(response)
    return text, model


# Tried in this order: cheapest/most-likely-to-just-work first. '' (omit the
# field) is last, not first, because a backend that ignores unknown fields
# harmlessly is common, but a genuine reasoning model with the field omitted
# reliably reasons at its default (often heavy) effort and burns the budget
# -- '' is the fallback for "none" not existing as a concept for this
# backend at all, not the first thing to try.
_REASONING_EFFORT_CANDIDATES = ('none', 'low', 'medium', 'high', '')


def calibrate_reasoning_effort(config: Config,
                                log=lambda line: None) -> str:
    """Probe the live backend to find a `reasoning_effort` value that lets
    it actually answer instead of exhausting CONFIG.max_tokens on hidden
    reasoning. Returns the first candidate from _REASONING_EFFORT_CANDIDATES
    that works; falls back to 'none' (this proxy's original default) with a
    logged warning if every candidate exhausts the budget, or if the
    backend cannot be reached at all -- calibration failing to find an
    answer is not reason to refuse to start the proxy.

    Why this exists: observed live across three different backends behind
    the same endpoint, the *wrong* reasoning_effort value does not merely
    fail to help -- it can turn a model that would otherwise work under no
    setting at all into one that reliably exhausts its token budget without
    ever answering. Since the correct value is a property of whichever
    model happens to be loaded, not of the proxy, guessing once at startup
    against the real backend beats hardcoding a default that is right for
    some models and actively wrong for others. LOG receives one line of
    human-readable progress per candidate tried, for main()'s startup
    output; callers that don't care can leave it as a no-op.
    """
    for candidate in _REASONING_EFFORT_CANDIDATES:
        label = candidate or '(omitted)'
        try:
            response = call_upstream(_probe_prompt(config),
                                      config,
                                      temperature=0.0,
                                      reasoning_effort=candidate,
                                      system_prompt=config.system_prompt)
            extract_completions(response)  # raises on failure
        except ReasoningBudgetExhausted:
            log(f'reasoning_effort={label}: exhausted the token budget '
                'without answering, trying next')
            continue
        except UpstreamError as exc:
            log(f'reasoning_effort={label}: backend error ({exc}); '
                'stopping calibration, falling back to "none"')
            return 'none'
        log(f'reasoning_effort={label}: works, using this')
        return candidate

    log('reasoning_effort: no candidate worked against this backend; '
        'falling back to "none". Consider setting --reasoning-effort '
        'explicitly if /complete requests fail.')
    return 'none'


def _extract_choice_text(choice: dict) -> str:
    """Pull message.content out of one /chat/completions choice.

    Raise UpstreamError if the choice does not have the expected shape,
    including the reasoning-model case where content is empty because the
    hidden reasoning pass consumed the whole token budget (finish_reason
    "length" with an empty content and non-empty reasoning_content) -- that
    is a distinguishable, actionable failure, not silently returned as an
    empty completion.
    """
    message = choice.get('message')
    text = message.get('content') if isinstance(message, dict) else None
    # Newer OpenAI-compatible backends may return content as a list of typed
    # parts ([{"type": "text", "text": "..."}]) instead of a bare string.
    # Concatenating the text parts costs nothing and turns a hard failure on
    # such a backend into a normal completion.
    if isinstance(text, list):
        text = ''.join(part.get('text', '') for part in text
                       if isinstance(part, dict) and isinstance(
                           part.get('text'), str))
    if not isinstance(text, str):
        raise UpstreamError('upstream choice had no message.content field')
    if (not text and choice.get('finish_reason') == 'length'
            and isinstance(message, dict) and message.get('reasoning_content')):
        raise ReasoningBudgetExhausted(
            'upstream spent its whole token budget on hidden reasoning '
            'and never answered; increase max_tokens or check '
            'reasoning_effort')
    return text


def _strip_code_fence(text: str) -> str:
    """Return the first markdown-fenced block's contents, or TEXT unchanged
    when there is no fence.

    SYSTEM_PROMPT does not instruct the model to avoid markdown -- that
    instruction was tried and found not to actually prevent fences even
    when present, so it was dropped rather than kept as dead weight (see
    the module docstring's autoresearch notes). Fences are simply stripped
    mechanically instead, unconditionally, on every completion.

    The fence is deliberately searched for anywhere in TEXT, not only at its
    very start. A small model very commonly answers with a prose preamble
    ahead of the fence -- "Here is the completion:\\n```pascal\\n..." -- and
    an earlier version of this function, which only fired when TEXT itself
    started with '```', passed that whole thing through verbatim: the
    preamble sentence landed in the user's Pascal buffer as if it were
    source. Everything outside the first fenced block is prose about the
    answer, not the answer, so it is discarded rather than kept.

    An unterminated fence (the model ran out of tokens mid-block) still
    yields the block's contents -- the text after the opening fence line is
    real source, and dropping it because the closing fence never arrived
    would throw away a usable completion.
    """
    fence_index = text.find('```')
    if fence_index == -1:
        return text
    # Skip the opening fence line entirely: it carries an optional info
    # string ('```pascal'), never source.
    first_newline = text.find('\n', fence_index)
    if first_newline == -1:
        # A lone '```' with nothing after it -- no block, nothing to keep.
        return text[:fence_index] if fence_index else ''
    body = text[first_newline + 1:]
    closing = body.find('```')
    if closing != -1:
        body = body[:closing]
    return body.strip()


def extract_completions(
        upstream_response: dict) -> tuple[str, str, str]:
    """Pull (completion, model, request_id) out of a /chat/completions JSON
    body's single choice. COMPLETION is choices[0].message.content
    verbatim, with any markdown code fence stripped (`_strip_code_fence`) --
    further cleanup (`sanitize_completion`) happens at the call site.
    """
    # `call_upstream` returns whatever `json.loads` produced, which is not
    # necessarily an object: a backend answering with a bare JSON array or
    # string used to reach `.get` here and raise AttributeError -- not an
    # UpstreamError, so `do_POST` never caught it and the handler died
    # without sending any response at all, leaving the client to see the
    # connection drop rather than a 502.
    if not isinstance(upstream_response, dict):
        raise UpstreamError('upstream response was not a JSON object')

    choices = upstream_response.get('choices')
    if not isinstance(choices, list) or not choices:
        raise UpstreamError('upstream response had no choices')
    choice = choices[0] if isinstance(choices[0], dict) else {}
    text = _strip_code_fence(_extract_choice_text(choice))

    model = upstream_response.get('model', '')
    request_id = upstream_response.get('id', '')
    return text, model if isinstance(model, str) else '', (
        request_id if isinstance(request_id, str) else '')


# --------------------------------------------------------------------------
# Output sanitization
# --------------------------------------------------------------------------


_ECHO_MIN_OVERLAP = 5

# Floors the approximate pass must clear before it will strip anything,
# measured on the matched candidate prefix. Both apply: an echo has to be
# long in tokens *and* substantial in actual characters.
#
# These are much stricter than _ECHO_MIN_OVERLAP because approximate
# matching strictly increases the chance of a match: it deliberately accepts
# text that merely resembles the buffer's tail. The floor has to rise to
# compensate, or the approximate pass reintroduces exactly the false
# positives that the character-level pass's floor exists to prevent.
#
# Both floors are calibrated against the concrete false positive that
# motivated the original floor -- back-to-back structural closers -- and
# against the shortest thing that is unambiguously a real echo, a retyped
# assignment statement.
#
# "END;" is 1 token pair and 4 characters; two nested blocks closing in a
# row, the case that ate real completions live, is 4 tokens and 8
# characters; three in a row is 6 tokens and 12 characters. A retyped
# "total := total + j;" is 7 tokens and 15 characters. So the floors sit
# between those two: 7 tokens and 14 characters admits the statement and
# excludes every run of up to three closers. Note the two floors are not
# redundant -- tokens alone would admit six one-character closers, and
# characters alone would admit two long identifiers.
_ECHO_MIN_APPROX_TOKENS = 7
_ECHO_MIN_APPROX_CHARS = 14

# Fraction of the matched candidate prefix that must align with the buffer's
# tail. 0.8 tolerates roughly one differing token in five -- enough for the
# renamed loop variable or dropped modifier a small model introduces while
# retyping, not enough for two genuinely different pieces of code to pass.
_ECHO_APPROX_MIN_SIMILARITY = 0.8

# Token budget for the alignment on each side. The DP below is O(m*n), so
# these bound its cost outright: 256x256 is ~65k cells, trivially fast, and
# far longer than any echo a model with a few hundred output tokens can
# produce. An echo is the model retyping recent context; it does not reach
# back kilobytes.
_ECHO_MAX_TOKENS = 256


def _echo_tokens(text: str) -> list[tuple[str, int]]:
    """Split TEXT into (TOKEN, RAW_END) pairs for echo comparison.

    A token is a case-folded run of identifier characters, or a single
    punctuation character; whitespace is dropped entirely rather than
    tokenized. RAW_END is the index in TEXT just past that token, so a match
    measured in tokens can be mapped back to an exact cut point in the raw
    text.

    Tokenizing rather than comparing characters is what makes indentation
    and keyword casing structurally invisible to the comparison instead of
    something it has to tolerate: Pascal 1981 is a case-insensitive dialect,
    so `begin` and `BEGIN` are the same token, and a model that reindents
    what it retypes has still echoed.
    """
    tokens: list[tuple[str, int]] = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char.isspace():
            index += 1
        elif char.isalnum() or char == '_':
            run = index
            while run < length and (text[run].isalnum() or text[run] == '_'):
                run += 1
            tokens.append((text[index:run].lower(), run))
            index = run
        else:
            tokens.append((char, index + 1))
            index += 1
    return tokens


def _is_identifier_char(char: str) -> bool:
    """Non-nil for a character that can appear inside a Pascal identifier."""
    return char.isalnum() or char == '_'


def _partial_token_echo_cut(buffer: str, candidate: str) -> int:
    """Index in CANDIDATE just past a restated partial identifier, or 0.

    The case this exists for: the cursor sits part-way through a word, and
    the model answers by retyping the whole word rather than continuing it.
    Typing `DISPO` and pressing TAB gets back `DISPOSE(p2);` instead of
    `SE(p2);`, and accepting that puts `DISPODISPOSE(p2);` in the buffer.

    Neither other pass can see this. The character-level pass finds the
    overlap exactly -- "DISPO" is 5 characters -- but its floor requires
    *more* than _ECHO_MIN_OVERLAP, and a partial identifier is routinely
    shorter than that; lowering the floor to catch it is not an option,
    since 4 characters is "END;" and that floor is the only thing keeping
    legitimate structural repetition out. The token-level pass cannot see it
    either: `DISPO` and `DISPOSE` are simply different tokens to it, and its
    floors are calibrated for multi-token echoes anyway.

    So this is matched on its own terms. It fires only when the buffer's
    prefix ends inside a word and the candidate opens with a word having
    that partial one as a case-insensitive prefix -- Pascal 1981 being a
    case-insensitive dialect, `dispose` continues `DISPO`. The cut is
    exactly the length of the partial word, which is the part the model
    restated.

    Being anchored to a word boundary on both sides is what makes a low
    threshold safe here, where it would not be for the other passes: a
    candidate that continues the partial word correctly (`SE(p2);`) does not
    begin with it and is left alone.
    """
    start = len(buffer)
    while start > 0 and _is_identifier_char(buffer[start - 1]):
        start -= 1
    partial = buffer[start:]
    if not partial:
        return 0

    end = 0
    while end < len(candidate) and _is_identifier_char(candidate[end]):
        end += 1
    head = candidate[:end]
    if len(head) < len(partial):
        return 0
    if head[:len(partial)].lower() != partial.lower():
        return 0
    return len(partial)


def _approximate_echo_cut(buffer: str, candidate: str) -> int:
    """Index in CANDIDATE just past an approximate echo of BUFFER's tail, or
    0 when there is no such echo worth stripping.

    The character-level pass in `strip_echo` only catches an echo the model
    reproduced byte for byte, and a small model routinely does not: it
    retypes the last statement with its own indentation, re-cases the
    dialect's keywords, renames a loop variable, or drops a modifier. A
    single differing character anywhere in the overlap collapses an exact
    match to nothing, and an exact match on *normalized* text is no better
    -- it still fails on the first substituted or missing token.

    So this is an approximate match, computed as a standard overlap
    alignment: the minimum edit distance between some suffix of the buffer's
    token stream and each prefix of the candidate's. The DP's first column
    is zeroed, which makes starting the buffer-side alignment at any token
    free -- that is the "some suffix" part -- while the final row is read
    across, giving the cost of aligning the whole chosen suffix against each
    candidate prefix in turn. The echo must run to the end of the buffer,
    because the buffer ends at the cursor and that is precisely where the
    model resumed writing, so only the final row is meaningful.

    Among candidate prefixes that clear both floors and the similarity
    threshold, the longest wins: a model that echoed twenty tokens should
    have all twenty stripped, not the first six.
    """
    buffer_tokens = _echo_tokens(buffer)[-_ECHO_MAX_TOKENS:]
    candidate_tokens = _echo_tokens(candidate)[:_ECHO_MAX_TOKENS]
    if not buffer_tokens or not candidate_tokens:
        return 0

    width = len(candidate_tokens)
    # previous[j] = edit distance between the empty buffer suffix and the
    # candidate's first j tokens, i.e. j insertions.
    previous = list(range(width + 1))
    for buffer_token, _ in buffer_tokens:
        # Zeroed first column: the buffer-side suffix may start here for
        # free, so everything consumed before it costs nothing.
        current = [0]
        for j in range(1, width + 1):
            cost = 0 if buffer_token == candidate_tokens[j - 1][0] else 1
            current.append(
                min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost))
        previous = current

    # Pick the *cheapest* qualifying alignment, breaking ties toward the
    # longest -- not simply the longest that clears the threshold. Those are
    # not the same choice, and the difference is a real over-strip: where
    # the candidate echoes seven tokens and then begins its actual
    # contribution, extending the match to eight tokens costs one insertion
    # but still scores 1 - 1/8 = 0.875, comfortably over the threshold. The
    # longest-wins rule would take it and eat the first token of the real
    # completion. Ranking by edit distance first refuses that: extending
    # into new material always costs, so the exact end of the echo is the
    # local minimum.
    best_cut = 0
    best_rank: tuple[int, int] | None = None
    characters = 0
    for j in range(1, width + 1):
        characters += len(candidate_tokens[j - 1][0])
        if j < _ECHO_MIN_APPROX_TOKENS or characters < _ECHO_MIN_APPROX_CHARS:
            continue
        if (1.0 - previous[j] / j) < _ECHO_APPROX_MIN_SIMILARITY:
            continue
        rank = (previous[j], -j)
        if best_rank is None or rank < best_rank:
            best_rank = rank
            best_cut = candidate_tokens[j - 1][1]
    return best_cut


def strip_echo(buffer: str, candidate: str) -> str:
    """Strip an echoed prefix of BUFFER's tail from the start of CANDIDATE,
    returning the residue.

    Two passes, cheapest and strictest first:

    1. A literal, character-level pass. Finds the longest exact match
       between some suffix of BUFFER and a prefix of CANDIDATE, and only
       treats it as a genuine echo -- worth stripping -- once that match is
       longer than _ECHO_MIN_OVERLAP characters. A short overlap is common,
       legitimate repetition, not the model retyping something already
       there: two nested blocks closing back-to-back both correctly end in
       "END;", and treating that kind of short, structurally-required repeat
       as an echo (an earlier version of this function did, comparing whole
       words with no minimum length) silently ate real completions down to
       nothing -- live in Emacs, not hypothetically. A longer overlap is not
       plausible as coincidence, so it is safe to treat as an echo.

    2. A partial-identifier pass (`_partial_token_echo_cut`), for the cursor
       sitting part-way through a word and the model retyping the whole word
       instead of continuing it -- `DISPO` answered with `DISPOSE(p2);`
       rather than `SE(p2);`. Too short for the first pass's floor and
       invisible to the third's tokenizer; see that function for why a low
       threshold is safe there specifically.

    3. An approximate, token-level pass (`_approximate_echo_cut`), run only
       when the others find nothing. This catches the echo the first pass
       structurally cannot see: a retype that differs from the buffer by
       indentation, keyword casing, a renamed identifier, or a dropped
       token. Any one of those collapses an exact match to nothing, and all
       of them are ordinary small-model behavior.

    The third pass is deliberately not just a relaxation of the first. It
    carries its own, much stricter floors (_ECHO_MIN_APPROX_TOKENS,
    _ECHO_MIN_APPROX_CHARS) and a similarity threshold, for the reason
    recorded there: approximate matching can only ever make more things
    match, so reusing the character-level floor here would resurrect the
    false positive that floor was introduced to kill. The strict pass keeps
    its low floor and catches short exact echoes; the approximate pass is
    reserved for long ones, where an accidental match is implausible.
    """
    max_check = min(len(buffer), len(candidate))
    overlap = 0
    for k in range(max_check, 0, -1):
        if buffer[-k:] == candidate[:k]:
            overlap = k
            break
    if overlap > _ECHO_MIN_OVERLAP:
        return candidate[overlap:]
    partial = _partial_token_echo_cut(buffer, candidate)
    if partial:
        return candidate[partial:]
    return candidate[_approximate_echo_cut(buffer, candidate):]


_SPECIAL_TOKEN_MARKER = '<|'

# Hard ceiling on a completion's total size, in characters. `max_lines`
# bounds the number of lines but says nothing about their length, so it does
# not bound this at all: a model that loses the plot and emits one
# unterminated string literal of 200,000 characters produces a single line
# and sails through the line cap. That text ends up in an Emacs overlay's
# `after-string`, where it stalls redisplay for the whole editor.
#
# 8192 is deliberately far above any plausible real completion (30 lines of
# Pascal is rarely over 1,500 characters) -- like `max_lines`, this is a
# safety valve against a runaway response, not a quality lever.
_MAX_COMPLETION_CHARS = 8192


def _strip_control_characters(text: str) -> str:
    """Remove C0 control characters other than newline and tab.

    `sanitize_completion` used to strip only NUL. Everything else in the C0
    range reaches the buffer intact, and a small model emits more of it than
    one would hope: a stray carriage return from CRLF-flavored training data
    lands as a literal ^M in the user's source, and an ESC begins what Emacs
    renders as an escape sequence. Newline and tab are kept because both are
    legitimate source characters; DEL (0x7f) is dropped with the rest.
    """
    return ''.join(char for char in text
                   if char in '\n\t' or not (ord(char) < 0x20 or ord(char) == 0x7f))


def sanitize_completion(text: str, max_lines: int = 30) -> str:
    """Enforce the NUL-free, marker-free, at-most-MAX_LINES output policy.

    This is a safety valve, not a quality lever: a completion running
    longer than a real single-statement or short-block continuation is
    welcome, not a bug to prevent ("too much completion is better than too
    little; extra can be stripped in some appropriate way" -- hence
    MAX_LINES defaults to a generous flat 30, not the old default of 1,
    which existed to solve a problem that turned out not to be one).
    MAX_LINES still exists to bound a genuinely runaway response, not to
    keep completions short.

    Extra lines in the raw text beyond MAX_LINES (the upstream stop sequence
    should prevent this, but a differently-configured backend might not
    honor it, and a model can simply overshoot) are truncated rather than
    failing the request -- trailing whitespace on the last kept line is
    preserved.

    Some backends (observed live: a reasoning/chat-tuned model served over
    the plain-completion endpoint) leak fragments of their internal special-
    token format -- e.g. Harmony channel markers like '<|channel|>' or the
    truncated '<|channel>' -- into the completion text instead of, or mixed
    in with, real source. '<|' does not occur in legitimate Pascal source,
    so truncating there is a safe, backend-agnostic guard: it stops leaked
    formatting from ever reaching the buffer. It is a containment measure,
    not a fix for a backend/model that is a poor fit for raw completion --
    see pascal-completion-plan.md.

    Leading blank lines are dropped. They are not a formatting nicety to
    preserve: the Emacs client previews only the completion's first line
    until the user asks for more, so a completion that opens with a blank
    line previews as nothing at all and reads as a broken TAB, even though a
    perfectly good completion is sitting one `M-n` away. Trailing whitespace
    on the last kept line is still preserved.
    """
    text = _strip_control_characters(text.replace('\0', ''))
    marker_index = text.find(_SPECIAL_TOKEN_MARKER)
    if marker_index != -1:
        text = text[:marker_index]
    text = text.lstrip('\n')
    text = '\n'.join(text.split('\n')[:max(max_lines, 1)])
    return text[:_MAX_COMPLETION_CHARS]


# --------------------------------------------------------------------------
# HTTP handler
# --------------------------------------------------------------------------


class CompletionHandler(BaseHTTPRequestHandler):
    config: Config  # set via make_server

    def log_message(self, fmt: str, *args) -> None:  # quieter default logging
        sys.stderr.write(f'pascal1981-completion-proxy: {fmt % args}\n')

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler naming)
        if self.path != '/health':
            self._send_json(404, {'error': 'not found'})
            return

        try:
            text, model = ping_upstream(self.config)
        except UpstreamError as exc:
            self._send_json(503, {'status': 'error', 'error': str(exc)})
            return

        self._send_json(
            200, {
                'status': 'ok',
                'upstream': self.config.chat_completions_url,
                'model': model or self.config.llm_model,
                'reasoning_effort': self.config.reasoning_effort,
                'sample_completion': text,
            })

    def do_POST(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler naming)
        if self.path != '/complete':
            self._send_json(404, {'error': 'not found'})
            return

        # A missing or non-numeric Content-Length is a malformed request, not
        # a reason to raise ValueError out of the handler and answer with a
        # 500 and a traceback.
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except (TypeError, ValueError):
            self._send_json(400, {'error': 'invalid Content-Length header'})
            return
        if length <= 0 or length > self.config.buffer_limit * 2:
            self._send_json(413, {'error': 'request body too large'})
            return

        # rfile.read(n) is not guaranteed to return n bytes in one call, and a
        # short read here surfaces as a baffling "invalid JSON" rather than as
        # the truncated request it actually is.
        chunks = []
        remaining = length
        while remaining > 0:
            chunk = self.rfile.read(remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b''.join(chunks)
        if remaining > 0:
            self._send_json(400, {'error': 'request body was truncated'})
            return

        # json.loads on undecodable bytes raises UnicodeDecodeError, which is
        # a ValueError but NOT a JSONDecodeError -- catching only the latter
        # let it escape as a 500.
        try:
            payload = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._send_json(400, {'error': 'invalid JSON'})
            return

        try:
            goal, buffer, line, column = validate_request(
                payload, self.config.buffer_limit)
        except RequestError as exc:
            self._send_json(400, {'error': str(exc)})
            return

        prefix = compute_prefix(buffer, line, column)

        try:
            prompt = build_prompt(goal, prefix, self.config.grammar_text)
            upstream_response = call_upstream(
                prompt,
                self.config,
                system_prompt=self.config.system_prompt)
            text, model, request_id = extract_completions(upstream_response)
        except UpstreamError as exc:
            self._send_json(502, {'error': str(exc)})
            return

        completion = sanitize_completion(
            strip_echo(prefix, text), self.config.max_lines)

        # An empty result is a normal outcome, not an error: `strip_echo` can
        # legitimately consume the entire candidate when the model did
        # nothing but retype the buffer, and `sanitize_completion` can
        # legitimately empty it when the model emitted only a special-token
        # marker. Report that as an empty list rather than as a list holding
        # an empty string -- a client checking whether it got a completion
        # cannot distinguish `[""]` from a real one by length, and the Emacs
        # client used to answer such a response by showing an empty ghost
        # overlay, which reads as TAB doing nothing at all.
        completions = [completion] if completion.strip() else []

        self._send_json(
            200, {
                'completions': completions,
                'model': model or self.config.llm_model,
                'request_id': request_id,
            })


class ForkingHTTPServer(socketserver.ForkingMixIn, HTTPServer):
    """One process per connection, not one thread.

    Deliberately forking rather than threading: `Config` is built once at
    startup and only ever read afterward, and no per-request state lives in
    this process (the elisp side owns all pending-request tracking) -- so
    nothing here needs threads' shared-memory semantics. Forking instead
    makes this reference implementation's concurrency model match what a
    future native pascal1981 port will actually use (fork-per-connection,
    proven in tests/integration/posix_pipe_fork.pas), rather than relying on
    a thread abstraction the dialect's runtime doesn't have.
    """


def make_server(config: Config) -> ForkingHTTPServer:
    handler = type('BoundCompletionHandler', (CompletionHandler,),
                    {'config': config})
    return ForkingHTTPServer((config.host, config.port), handler)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Local HTTP proxy for pascal1981-mode LLM completion.')
    parser.add_argument(
        '--host',
        default='127.0.0.1',
        help='Host the proxy itself listens on. Default: 127.0.0.1.')
    parser.add_argument(
        '--port',
        type=int,
        default=8790,
        help='Port the proxy itself listens on. Default: 8790.')
    parser.add_argument(
        '--llm-base-url',
        default='http://127.0.0.1:8080/v1',
        help=('Base URL of the OpenAI-completions-compatible backend '
              '(e.g. a local llama.cpp server). Default: '
              'http://127.0.0.1:8080/v1, i.e. localhost, port 8080.'))
    parser.add_argument(
        '--llm-model',
        default='default',
        help=('Model name sent in the "model" field of every upstream '
              'request. Most single-model llama.cpp/LM Studio servers '
              'ignore this and serve whatever is loaded. Default: '
              '"default".'))
    parser.add_argument(
        '--buffer-limit',
        type=int,
        default=65536,
        help=('Maximum accepted "buffer" size, in characters, on a '
              '/complete request. Default: 65536.'))
    parser.add_argument(
        '--max-tokens',
        type=int,
        default=512,
        help=('Token budget per completion request, including any hidden '
              'reasoning a model performs before answering. Default: 512 '
              '-- higher than a non-reasoning backend needs, but a '
              'reasoning backend can spend most of it before ever '
              'writing an answer; see --grammar-file for a case that can '
              'need more.'))
    parser.add_argument(
        '--temperature',
        type=float,
        default=0.2,
        help='Sampling temperature for completion requests. Default: 0.2.')
    parser.add_argument(
        '--upstream-timeout',
        type=float,
        default=20.0,
        help=('Seconds to wait for the upstream backend before giving up. '
              'Default: 20.0. Keep this equal to (never longer than) '
              "pascal1981-completion-timeout on the Emacs side, or the "
              'client gives up first and never sees this proxy\'s error.'))
    parser.add_argument(
        '--reasoning-effort',
        default='auto',
        help=('Value sent as the top-level "reasoning_effort" field on '
              'every /chat/completions request: "none", "low", "medium", '
              '"high", or "" to omit the field entirely (for a backend '
              'that rejects unknown fields). Default: "auto", which '
              'self-calibrates against the live backend at startup -- '
              'set this explicitly only to skip that calibration.'))
    parser.add_argument(
        '--grammar-file',
        default='',
        help=('Path to an EBNF grammar file (e.g. docs/ebnf_grammar.md) to '
              'prepend as reference context on every completion request. '
              'Optional; increases prompt size and upstream latency, and '
              'was independently tested and found not to help completion '
              'quality -- kept available in case a future prompt shape '
              'changes that, not because it is currently recommended.'))
    parser.add_argument(
        '--system-prompt-file',
        default='',
        help=('Path to a text file overriding the completion system prompt '
              '(default: the bundled tools/prompts/system_prompt.txt).'))
    parser.add_argument(
        '--max-lines',
        type=int,
        default=30,
        help=('Safety-valve cap on completion length, in lines -- not a '
              'quality lever. A completion longer than this is truncated '
              'rather than the request failing. Default: 30.'))
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args(sys.argv[1:])
    config = Config(
        host=args.host,
        port=args.port,
        llm_base_url=args.llm_base_url,
        llm_model=args.llm_model,
        buffer_limit=args.buffer_limit,
        max_tokens=args.max_tokens,
        temperature=args.temperature,
        upstream_timeout=args.upstream_timeout,
        reasoning_effort=args.reasoning_effort,
        grammar_file=args.grammar_file,
        system_prompt=(load_prompt_override(args.system_prompt_file)
                      if args.system_prompt_file else None),
        max_lines=args.max_lines,
    )

    if config.reasoning_effort == 'auto':
        print(
            'pascal1981-completion-proxy: --reasoning-effort not set, '
            f'calibrating against {config.chat_completions_url} ...',
            file=sys.stderr)
        config.reasoning_effort = calibrate_reasoning_effort(
            config, log=lambda line: print(
                f'pascal1981-completion-proxy: {line}', file=sys.stderr))

    server = make_server(config)
    print(
        f'pascal1981-completion-proxy: listening on '
        f'http://{config.host}:{config.port}/complete, upstream '
        f'{config.chat_completions_url}, reasoning_effort='
        f'{config.reasoning_effort or "(omitted)"}'
        + (f', grammar context from {config.grammar_file}'
           if config.grammar_file else ''),
        file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
