#!/usr/bin/env python3
"""Local HTTP proxy: pascal1981-mode <-> an OpenAI-completions-compatible API.

Emacs never starts this process. A person starts it by hand (see
elisp/README.md) and it keeps running until they stop it; the mode is only
ever an HTTP client of whatever is already listening on
PASCAL1981_PROXY_HOST:PASCAL1981_PROXY_PORT.

Protocol (see pascal-completion-plan.md):

    POST /complete
    {"goal": "...", "buffer": "...", "cursor": {"line": N, "column": N}}
    ->
    {"completion": "...", "model": "...", "request_id": "..."}

The upstream backend is configured by LLM_BASE_URL (default
http://127.0.0.1:8080/v1, i.e. a local llama.cpp server) and reached through
its OpenAI-compatible /chat/completions endpoint. LLM_API_KEY is optional;
llama.cpp needs none. Only stdlib is used -- no extra dependency to install
before the proxy can start.

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
PASCAL1981_PROXY_REASONING_EFFORT can be set to an empty string to omit it.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------


def load_grammar(path: str) -> str:
    """Read the grammar reference file at PATH. Raise OSError on failure --
    a bad --grammar-file / PASCAL1981_PROXY_GRAMMAR_FILE should fail the
    proxy at startup, not silently drop grammar context on every request."""
    with open(path, encoding='utf-8') as handle:
        return handle.read()


class Config:
    """Proxy configuration, read from the environment (and optionally CLI
    overrides) at startup."""

    def __init__(self,
                 env: dict[str, str] | None = None,
                 grammar_file: str | None = None) -> None:
        env = os.environ if env is None else env
        self.host = env.get('PASCAL1981_PROXY_HOST', '127.0.0.1')
        self.port = int(env.get('PASCAL1981_PROXY_PORT', '8790'))
        self.llm_base_url = env.get('LLM_BASE_URL',
                                     'http://127.0.0.1:8080/v1').rstrip('/')
        self.llm_api_key = env.get('LLM_API_KEY', '')
        self.llm_model = env.get('LLM_MODEL', 'default')
        self.buffer_limit = int(env.get('PASCAL1981_PROXY_BUFFER_LIMIT',
                                         '65536'))
        # 512, not the ~32 a non-reasoning backend would need: observed live,
        # a reasoning model can spend 200-360+ tokens in reasoning_content
        # before ever writing an answer, even with reasoning_effort tuned to
        # the value that lets it actually finish -- and that cost rises
        # further with a larger prompt (e.g. --grammar-file's ~2300 extra
        # prompt tokens pushed one case from ~200 to 359 reasoning tokens in
        # testing). A tighter budget for a backend that never reasons just
        # means the request finishes early once its answer is written; it
        # does not cost extra latency there, so the larger default is safe
        # for both kinds of backend, not just a concession to one of them.
        self.max_tokens = int(env.get('PASCAL1981_PROXY_MAX_TOKENS', '512'))
        self.temperature = float(
            env.get('PASCAL1981_PROXY_TEMPERATURE', '0.2'))
        # 20s, not the 5-10s a non-reasoning backend would need: a
        # reasoning-heavy completion at ~90 tokens/s can take several
        # seconds even before writing an answer.
        self.upstream_timeout = float(
            env.get('PASCAL1981_PROXY_UPSTREAM_TIMEOUT', '20'))

        # Sent as a top-level "reasoning_effort" field on every request to
        # /chat/completions. Set to an empty string to omit the field
        # entirely, for a backend that rejects unknown fields outright.
        #
        # Left unset, this is the literal sentinel "auto": observed live,
        # the *wrong* value here does not just fail to help, it actively
        # breaks a model that would otherwise work fine (a reasoning model
        # given the wrong effort level burns its whole token budget without
        # ever answering, and a non-reasoning model given a value meant for
        # a different, reasoning-heavy model can do the same). Since the
        # correct value is a property of whichever model happens to be
        # loaded right now, not of the proxy, "auto" tells main() to run
        # calibrate_reasoning_effort() against the live backend at startup
        # and resolve this field before serving. Setting the environment
        # variable explicitly (to "none", "low", "medium", "high", or "")
        # always skips calibration and is used as-is -- an operator's
        # explicit choice is never second-guessed.
        self.reasoning_effort = env.get('PASCAL1981_PROXY_REASONING_EFFORT',
                                         'auto')

        # Optional: prepend the dialect's EBNF grammar to every prompt as
        # reference context. Off by default -- it costs prompt tokens and
        # upstream latency on every eligible-TAB request, so it is opt-in via
        # --grammar-file or PASCAL1981_PROXY_GRAMMAR_FILE, not auto-detected
        # from docs/ebnf_grammar.md even though that file is a natural fit.
        self.grammar_file = (grammar_file if grammar_file is not None else
                              env.get('PASCAL1981_PROXY_GRAMMAR_FILE', ''))
        self.grammar_text = (load_grammar(self.grammar_file)
                              if self.grammar_file else '')

    @property
    def chat_completions_url(self) -> str:
        return f'{self.llm_base_url}/chat/completions'


# --------------------------------------------------------------------------
# Request validation
# --------------------------------------------------------------------------


class RequestError(Exception):
    """Malformed /complete request. Message is safe to return to the client."""


def validate_request(payload: object, buffer_limit: int) -> tuple[str, str, int, int]:
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


def build_prompt(goal: str, prefix: str, grammar: str = '') -> str:
    """Build the user-message content sent upstream (see SYSTEM_PROMPT for
    the accompanying system message).

    The content is mostly the literal source prefix, formatted so the model
    sees it as "the code so far" to continue -- that reads naturally
    alongside SYSTEM_PROMPT's instruction to complete at the end of it. A
    non-empty GOAL is carried as a one-line Pascal comment immediately
    before the prefix, kept off its own line's indentation so it cannot be
    mistaken for buffer content.

    A non-empty GRAMMAR (the dialect's EBNF reference, opt-in via
    --grammar-file) is prepended ahead of that, marked with a plain '#'
    header/footer rather than a Pascal '{ }' or '(* *)' comment: the
    grammar text itself contains both of those delimiter pairs (as EBNF
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


SYSTEM_PROMPT = (
    'You are an inline code-completion engine for the 1981 IBM Pascal '
    'dialect. You are given Pascal source code ending exactly at the '
    'insertion point. Respond with ONLY the exact text to insert there to '
    'continue the current line: no explanation, no markdown, no code '
    'fences, no repeated source, and never a newline. If nothing sensible '
    'completes the line, respond with an empty string.')


def call_upstream(prompt: str,
                   config: Config,
                   max_tokens: int | None = None,
                   temperature: float | None = None,
                   reasoning_effort: str | None = None) -> dict:
    """POST PROMPT (the user-message content from `build_prompt`) to the
    configured /chat/completions endpoint, alongside SYSTEM_PROMPT. Return
    the parsed JSON response. Raise UpstreamError on any transport, timeout,
    HTTP, or JSON failure.

    MAX_TOKENS / TEMPERATURE / REASONING_EFFORT default to CONFIG's values;
    callers that want to probe a value without touching the configured
    completion behavior (see `ping_upstream`, `calibrate_reasoning_effort`)
    can override them. REASONING_EFFORT follows CONFIG.reasoning_effort's
    convention: '' omits the field, and the sentinel 'auto' is never valid
    here -- calibrate_reasoning_effort is what resolves 'auto' into a real
    value or '', so if it somehow still reaches this function it is treated
    the same as '' (omit) rather than sent upstream literally.
    """
    payload = {
        'model':
            config.llm_model,
        'messages': [
            {
                'role': 'system',
                'content': SYSTEM_PROMPT
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
    response = call_upstream(_probe_prompt(config), config, temperature=0.0)
    text, model, _request_id = extract_completion(response)
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
                                      reasoning_effort=candidate)
            extract_completion(response)  # raises on failure
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
        'falling back to "none". Consider setting '
        'PASCAL1981_PROXY_REASONING_EFFORT explicitly if /complete '
        'requests fail.')
    return 'none'


def extract_completion(upstream_response: dict) -> tuple[str, str, str]:
    """Pull (completion, model, request_id) out of a /chat/completions JSON
    body: choices[0].message.content.

    Raise UpstreamError if the response does not have the expected shape,
    including the reasoning-model case where content is empty because the
    hidden reasoning pass consumed the whole token budget (finish_reason
    "length" with an empty content and non-empty reasoning_content) -- that
    is a distinguishable, actionable failure, not silently returned as an
    empty completion.
    """
    choices = upstream_response.get('choices')
    if not isinstance(choices, list) or not choices:
        raise UpstreamError('upstream response had no choices')
    choice = choices[0] if isinstance(choices[0], dict) else {}
    message = choice.get('message')
    text = message.get('content') if isinstance(message, dict) else None
    if not isinstance(text, str):
        raise UpstreamError('upstream choice had no message.content field')
    if (not text and choice.get('finish_reason') == 'length'
            and isinstance(message, dict) and message.get('reasoning_content')):
        raise ReasoningBudgetExhausted(
            'upstream spent its whole token budget on hidden reasoning '
            'and never answered; increase max_tokens or check '
            'reasoning_effort')
    model = upstream_response.get('model', '')
    request_id = upstream_response.get('id', '')
    return text, model if isinstance(model, str) else '', (
        request_id if isinstance(request_id, str) else '')


# --------------------------------------------------------------------------
# Output sanitization
# --------------------------------------------------------------------------


_SPECIAL_TOKEN_MARKER = '<|'


def sanitize_completion(text: str) -> str:
    """Enforce the single-line, NUL-free, marker-free output policy.

    A newline in the raw text (the upstream stop sequence should prevent
    this, but a differently-configured backend might not honor it) truncates
    the completion at the first line rather than failing the request --
    trailing whitespace on that first line is preserved.

    Some backends (observed live: a reasoning/chat-tuned model served over
    the plain-completion endpoint) leak fragments of their internal special-
    token format -- e.g. Harmony channel markers like '<|channel|>' or the
    truncated '<|channel>' -- into the completion text instead of, or mixed
    in with, real source. '<|' does not occur in legitimate Pascal source,
    so truncating there is a safe, backend-agnostic guard: it stops leaked
    formatting from ever reaching the buffer. It is a containment measure,
    not a fix for a backend/model that is a poor fit for raw single-line
    completion -- see pascal-completion-plan.md.
    """
    text = text.replace('\0', '')
    marker_index = text.find(_SPECIAL_TOKEN_MARKER)
    if marker_index != -1:
        text = text[:marker_index]
    return text.split('\n', 1)[0]


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

        length = int(self.headers.get('Content-Length', '0'))
        if length <= 0 or length > self.config.buffer_limit * 2:
            self._send_json(413, {'error': 'request body too large'})
            return
        raw = self.rfile.read(length)

        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            self._send_json(400, {'error': 'invalid JSON'})
            return

        try:
            goal, buffer, line, column = validate_request(
                payload, self.config.buffer_limit)
        except RequestError as exc:
            self._send_json(400, {'error': str(exc)})
            return

        prefix = compute_prefix(buffer, line, column)
        prompt = build_prompt(goal, prefix, self.config.grammar_text)

        try:
            upstream_response = call_upstream(prompt, self.config)
            text, model, request_id = extract_completion(upstream_response)
        except UpstreamError as exc:
            self._send_json(502, {'error': str(exc)})
            return

        completion = sanitize_completion(text)
        self._send_json(
            200, {
                'completion': completion,
                'model': model or self.config.llm_model,
                'request_id': request_id,
            })


def make_server(config: Config) -> ThreadingHTTPServer:
    handler = type('BoundCompletionHandler', (CompletionHandler,),
                    {'config': config})
    return ThreadingHTTPServer((config.host, config.port), handler)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Local HTTP proxy for pascal1981-mode LLM completion.')
    parser.add_argument(
        '--grammar-file',
        default=None,
        help=('Path to an EBNF grammar file (e.g. docs/ebnf_grammar.md) to '
              'prepend as reference context on every completion request. '
              'Optional; increases prompt size and upstream latency. '
              'Falls back to PASCAL1981_PROXY_GRAMMAR_FILE if omitted.'))
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args(sys.argv[1:])
    config = Config(grammar_file=args.grammar_file)

    if config.reasoning_effort == 'auto':
        print(
            'pascal1981-completion-proxy: PASCAL1981_PROXY_REASONING_EFFORT '
            f'not set, calibrating against {config.chat_completions_url} ...',
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
