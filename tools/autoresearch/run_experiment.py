#!/usr/bin/env python3
"""Autoresearch harness: run tools/pascal1981_completion_proxy.py against
the corpus under corpus/ for every entry of a run matrix, score the
resulting completions, and persist raw results as JSON under results/.

This script never edits the proxy or the corpus; it only talks to the
proxy's own HTTP contract (/health, /complete) and, for judging, calls a
backend LLM directly through the proxy module's own `call_upstream` /
`Config` (imported, not reimplemented) -- so a run's tunable surface is
exactly prompts (sidecar files) + proxy CLI flags + corpus, matching the
autoresearch plan.

Usage:
    python3 tools/autoresearch/run_experiment.py matrix.json

Backend base URLs are never hard-coded here or in the matrix file; each
matrix entry names an environment variable (e.g. "PASCAL1981_LLM1_URL")
that must hold the backend's base URL at run time -- see matrix.example.json.
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
AUTORESEARCH_DIR = pathlib.Path(__file__).resolve().parent
CORPUS_DIR = AUTORESEARCH_DIR / 'corpus'
RESULTS_DIR = AUTORESEARCH_DIR / 'results'
JUDGE_PROMPT_PATH = AUTORESEARCH_DIR / 'judge_prompt.txt'
PROXY_SCRIPT = REPO_ROOT / 'tools' / 'pascal1981_completion_proxy.py'

# tools/ isn't a package; import the proxy module by path so this script
# can reuse its Config/call_upstream/extract_completions rather than
# reimplementing an OpenAI-compatible HTTP client.
sys.path.insert(0, str(REPO_ROOT / 'tools'))
import pascal1981_completion_proxy as proxy  # noqa: E402

AXES = ('correctness', 'anticipation', 'efficiency', 'aesthetics')

# How many lines of buffer immediately before the cursor to show the judge.
# Bounds judge-prompt size on long truncated-program items; the judge
# doesn't need the whole file, just enough context to see what's germane.
JUDGE_CONTEXT_LINES = 25

# How many top candidates per corpus item get sent to the judge, to bound
# the number of judge LLM calls per run (a run may have dozens of items and
# several candidates each).
JUDGE_CANDIDATE_CAP = 2

_CODE_FENCE_RE = re.compile(r'^```[a-zA-Z]*\n|\n```\s*$')


def load_corpus() -> list[dict]:
    items = []
    for path in sorted(CORPUS_DIR.glob('*.json')):
        items.append(json.loads(path.read_text(encoding='utf-8')))
    return items


def load_matrix(path: pathlib.Path) -> list[dict]:
    return json.loads(path.read_text(encoding='utf-8'))['matrix']


def wait_for_health(base_url: str, timeout: float = 90.0) -> bool:
    """Wait for the proxy at BASE_URL to be ready to serve, up to TIMEOUT.

    Deliberately does NOT poll GET /health: that endpoint calls
    ping_upstream on every single request (see CompletionHandler.do_GET in
    pascal1981_completion_proxy.py) -- it's a live liveness probe against
    the real backend, not a cheap "is the process up" check. Polling it
    repeatedly was observed live to itself generate real backend load: each
    poll attempt's short client-side timeout abandoned the connection
    before ping_upstream finished, but the backend (configured for one
    connection at a time) kept working the abandoned request anyway,
    piling up ahead of the harness's real completion requests and making
    the whole run far slower and less predictable than the corpus size
    alone would suggest -- and, server-side, surfaced as a wall of
    BrokenPipeError tracebacks for each abandoned probe.

    A plain TCP connect is enough: by the time the proxy's make_server()
    call binds and listens (see main() in the proxy module), startup
    calibration has already finished, so "accepts a TCP connection" and
    "ready to serve /complete" are the same moment -- no LLM round trip
    needed to observe it.

    90s, not a short timeout: still needs to comfortably span the proxy's
    own startup calibration step (calibrate_reasoning_effort), which can
    take tens of seconds against a reasoning-heavy backend trying several
    reasoning_effort candidates before finding one that works, and that
    step runs entirely before the socket is even opened.
    """
    import socket
    host, _, rest = base_url.partition('://')[2].partition('/')
    hostname, _, port_str = host.partition(':')
    port = int(port_str)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((hostname, port), timeout=1.0):
                return True
        except OSError:
            pass
        time.sleep(0.3)
    return False


def start_proxy(entry: dict, port: int) -> subprocess.Popen:
    backend_url = os.environ.get(entry['backend_env_var'])
    if not backend_url:
        raise RuntimeError(
            f'matrix entry {entry["label"]!r} needs env var '
            f'{entry["backend_env_var"]!r} set to the backend base URL')
    args = [sys.executable, str(PROXY_SCRIPT),
            '--port', str(port), '--llm-base-url', backend_url]
    for flag, value in entry.get('proxy_args', {}).items():
        args.extend([flag, str(value)])
    # Let the proxy's own stdout/stderr (including its startup calibration
    # log lines -- see calibrate_reasoning_effort in the proxy module) go
    # straight to this process's stderr rather than a PIPE: PIPE requires
    # something to actively drain it, and a plain proc.stdout.read() on a
    # still-running child blocks until the child exits, which is exactly
    # what made an earlier version of this function deadlock on the health-
    # check failure path. Inheriting the fd instead means the harness's own
    # progress lines (see run_matrix_entry) interleave live with the
    # proxy's, so a slow/stuck calibration is visible as it happens, not
    # silently buffered.
    proc = subprocess.Popen(args, stdout=sys.stderr, stderr=subprocess.STDOUT,
                             text=True, cwd=REPO_ROOT)
    return proc


def post_complete(base_url: str, item: dict, n: int,
                   timeout: float = 60.0) -> dict:
    payload = {
        'goal': item['goal'],
        'buffer': item['buffer'],
        'cursor': item['cursor'],
        'n': n,
    }
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        f'{base_url}/complete', data=data,
        headers={'Content-Type': 'application/json'}, method='POST')
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode('utf-8'))


def _flag_value(proxy_args: dict, *flags: str) -> str | None:
    for flag in flags:
        if flag in proxy_args:
            return str(proxy_args[flag])
    return None


def estimate_prompt_chars(entry: dict, item: dict, n: int) -> int:
    """Character count of the exact system + user prompt text this matrix
    entry's proxy config would send upstream for ITEM, reusing the proxy
    module's own build_prompt/multi_system_prompt (not a reimplementation)
    so the number reflects the real assembled prompt, including any
    --grammar-file or prompt-file override in ENTRY['proxy_args'].

    This is a prompt-*size* efficiency signal distinct from the judge's
    "efficiency" axis (which scores the candidate's usefulness per
    character typed by the user). It matters most for small local models:
    a bloated prompt (e.g. --grammar-file's ~2300 extra characters) can
    overwhelm a small model's effective context handling even when it
    technically fits the context window -- see the module docstring's
    Autoresearch notes in pascal1981_completion_proxy.py. Character count,
    not a real tokenizer count, since the harness has no dependency on
    either backend's tokenizer and both backends' /complete responses
    don't surface upstream "usage" token counts to the proxy's client (see
    extract_completions) -- characters are the closest signal obtainable
    without changing the proxy.
    """
    proxy_args = entry.get('proxy_args', {})
    grammar_path = _flag_value(proxy_args, '--grammar-file')
    grammar_text = ((REPO_ROOT / grammar_path).read_text(encoding='utf-8')
                     if grammar_path else '')

    system_prompt_path = _flag_value(proxy_args, '--system-prompt-file')
    system_prompt_text = (proxy.load_prompt_override(system_prompt_path)
                            if system_prompt_path else proxy.SYSTEM_PROMPT)

    multi_system_path = _flag_value(proxy_args, '--multi-system-prompt-file')
    multi_system_template = (proxy.load_prompt_override(multi_system_path)
                               if multi_system_path
                               else proxy._MULTI_SYSTEM_PROMPT_TEMPLATE)

    multi_prefix_path = _flag_value(proxy_args, '--multi-user-prefix-file')
    multi_prefix_template = (proxy.load_prompt_override(multi_prefix_path)
                               if multi_prefix_path
                               else proxy._MULTI_USER_PREFIX_TEMPLATE)

    prefix = proxy.compute_prefix(item['buffer'], item['cursor']['line'],
                                   item['cursor']['column'])
    if n > 1:
        system_text = proxy.multi_system_prompt(n, multi_system_template)
        multi_prefix = multi_prefix_template.format(n=n)
    else:
        system_text = system_prompt_text
        multi_prefix = ''
    user_text = proxy.build_prompt(item['goal'], prefix, grammar_text,
                                    multi_prefix)
    return len(system_text) + len(user_text)


def find_compiler_binary() -> pathlib.Path | None:
    for name in ('pascal1981-native', 'pascal1981'):
        candidate = REPO_ROOT / 'bin' / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def compile_check(compiler: pathlib.Path | None, buffer: str,
                   candidate: str) -> dict | None:
    """Attempt to compile BUFFER + CANDIDATE with COMPILER. Return a dict
    with 'passed' (bool) and 'diagnostic' (str, only on failure), or None
    if no compiler binary is available (see find_compiler_binary -- this
    is a soft skip, not a failure, since building the compiler is a
    separate, optional prerequisite from running this harness)."""
    if compiler is None:
        return None
    source = buffer + candidate
    with tempfile.TemporaryDirectory() as tmp:
        src_path = pathlib.Path(tmp) / 'candidate.pas'
        src_path.write_text(source, encoding='utf-8')
        try:
            proc = subprocess.run(
                [str(compiler), str(src_path)],
                cwd=tmp, capture_output=True, text=True, timeout=30)
        except subprocess.TimeoutExpired:
            return {'passed': False, 'diagnostic': 'compiler timed out'}
        if proc.returncode == 0:
            return {'passed': True}
        diag = (proc.stderr or proc.stdout or '').strip()
        return {'passed': False, 'diagnostic': diag[-2000:]}


def _strip_code_fence(text: str) -> str:
    return _CODE_FENCE_RE.sub('', text.strip())


def judge_candidate(judge_config: proxy.Config, judge_prompt_template: str,
                     item: dict, candidate: str,
                     compile_result: dict | None) -> dict:
    buffer_lines = item['buffer'].splitlines()
    buffer_window = '\n'.join(buffer_lines[-JUDGE_CONTEXT_LINES:])
    if compile_result is None:
        compile_note = ''
    elif compile_result['passed']:
        compile_note = ('\n(Objective check: buffer + candidate compiled '
                         'successfully with the real Pascal 1981 compiler.)')
    else:
        compile_note = (
            '\n(Objective check: buffer + candidate FAILED to compile with '
            f'the real Pascal 1981 compiler: {compile_result["diagnostic"]})')
    prompt = judge_prompt_template.format(
        goal=item['goal'],
        buffer_window=buffer_window,
        reference_continuation=item.get('reference_continuation', ''),
        candidate=candidate,
        compile_check_note=compile_note,
    )
    try:
        response = proxy.call_upstream(
            prompt, judge_config,
            max_tokens=judge_config.max_tokens, temperature=0.0,
            system_prompt='You are a strict, terse code-review grader.')
        texts, _model, _request_id, _indices = proxy.extract_completions(
            response)
    except proxy.UpstreamError as exc:
        # Calibration (see run_matrix_entry) only tunes reasoning_effort
        # against a short fixed probe prompt -- the real judge prompt here
        # varies in length per item (buffer window, reference continuation,
        # candidate all differ) and can still exhaust the token budget on
        # hidden reasoning for a longer item even after calibration picked
        # a value that works for the probe. One candidate failing to score
        # should not crash the whole run -- see run_matrix_entry's per-item
        # loop, which otherwise has no protection against this propagating
        # all the way out of main() (observed live).
        return {'error': f'judge call failed: {exc!r}'}
    raw = texts[0] if texts else ''
    try:
        scores = json.loads(_strip_code_fence(raw))
    except (json.JSONDecodeError, IndexError):
        return {'error': f'judge returned unparseable output: {raw!r}'}
    result = {}
    for axis in AXES:
        value = scores.get(axis)
        if not isinstance(value, int) or not (1 <= value <= 5):
            return {'error': f'judge omitted/misscored axis {axis!r}: {scores!r}'}
        result[axis] = value
        result[f'{axis}_why'] = scores.get(f'{axis}_why', '')
    return result


def run_matrix_entry(entry: dict, corpus: list[dict],
                      judge_backend_env_var: str, port: int,
                      skip_judge: bool = False) -> dict:
    label = entry['label']
    print(f'--- running matrix entry {label!r} ---', file=sys.stderr)
    proc = start_proxy(entry, port)
    base_url = f'http://127.0.0.1:{port}'
    try:
        if not wait_for_health(base_url):
            # The proxy's own output already streamed to stderr live (see
            # start_proxy) as this polled, so there's nothing further to
            # capture here -- just report the failure and let `finally`
            # tear the process down.
            raise RuntimeError(f'proxy for {label!r} never became healthy '
                                f'within the wait_for_health timeout; see '
                                f'its interleaved stderr output above')

        compiler = find_compiler_binary()
        if compiler is None:
            print('note: no compiler binary found under bin/ -- skipping '
                  'objective compile checks for this run', file=sys.stderr)

        judge_backend_url = (None if skip_judge else
                              os.environ.get(judge_backend_env_var))
        judge_config = None
        if judge_backend_url:
            # 700, not a tighter budget: observed live, a reasoning-heavy
            # judge backend can exhaust a 300-400 token budget on hidden
            # reasoning alone even after calibration (calibration only
            # tunes against a short fixed probe, not the real, longer,
            # per-item judge prompt -- see judge_candidate's UpstreamError
            # handling for the case where this still isn't enough).
            judge_config = proxy.Config(llm_base_url=judge_backend_url,
                                         max_tokens=700)
            # judge_config.reasoning_effort defaults to the "auto" sentinel,
            # which call_upstream (see judge_candidate) treats as "omit the
            # field" rather than as "run calibration" -- only main() ever
            # resolves "auto" into a real value, and the harness never goes
            # through main(). Left unresolved, a reasoning-heavy judge
            # backend reliably exhausts its token budget on hidden
            # reasoning and never returns a score (observed live). Run the
            # same calibration main() would, against the judge backend.
            print(f'[{label}] calibrating judge backend '
                  f'({judge_backend_url})...', file=sys.stderr)
            judge_config.reasoning_effort = proxy.calibrate_reasoning_effort(
                judge_config, log=lambda line: print(
                    f'[{label}] judge calibration: {line}', file=sys.stderr))
        judge_prompt_template = JUDGE_PROMPT_PATH.read_text(encoding='utf-8')
        print(f'[{label}] completions backend: {entry["backend_env_var"]}='
              f'{os.environ.get(entry["backend_env_var"])}', file=sys.stderr)
        print(f'[{label}] judge backend: {judge_backend_env_var}='
              f'{judge_backend_url or "(unset -- judging will be skipped)"}',
              file=sys.stderr)

        item_results = []
        for i, item in enumerate(corpus):
            n = entry.get('n', 1)
            prompt_chars = estimate_prompt_chars(entry, item, n)
            t0 = time.monotonic()
            print(f'[{label}] ({i + 1}/{len(corpus)}) {item["id"]}: '
                  f'requesting completion (n={n})...', file=sys.stderr)
            try:
                response = post_complete(base_url, item, n)
                latency = time.monotonic() - t0
            except (urllib.error.URLError, OSError, TimeoutError) as exc:
                print(f'[{label}] ({i + 1}/{len(corpus)}) {item["id"]}: '
                      f'completion request failed: {exc}', file=sys.stderr)
                item_results.append({'id': item['id'], 'error': str(exc)})
                continue
            candidates = response.get('completions', [])
            print(f'[{label}] ({i + 1}/{len(corpus)}) {item["id"]}: '
                  f'got {len(candidates)} candidate(s) in {latency:.1f}s',
                  file=sys.stderr)
            candidate_results = []
            for idx, candidate in enumerate(candidates[:JUDGE_CANDIDATE_CAP]):
                compile_result = None
                if idx == 0 and item.get('compiles_when_appended'):
                    compile_result = compile_check(
                        compiler, item['buffer'], candidate)
                if judge_config is not None:
                    print(f'[{label}] ({i + 1}/{len(corpus)}) {item["id"]}: '
                          f'sending candidate {idx} to judge '
                          f'({judge_backend_url})...', file=sys.stderr)
                if judge_config is not None:
                    judge_result = judge_candidate(
                        judge_config, judge_prompt_template, item, candidate,
                        compile_result)
                elif skip_judge:
                    judge_result = {'error': 'judging skipped (--skip-judge)'}
                else:
                    judge_result = {
                        'error': f'no {judge_backend_env_var} set, judging skipped'
                    }
                print(f'[{label}] ({i + 1}/{len(corpus)}) {item["id"]}: '
                      f'judge result for candidate {idx}: {judge_result}',
                      file=sys.stderr)
                candidate_results.append({
                    'candidate': candidate,
                    'compile_check': compile_result,
                    'judge': judge_result,
                })
            item_results.append({
                'id': item['id'],
                'latency_seconds': latency,
                'prompt_chars': prompt_chars,
                'candidates': candidate_results,
            })
        return {'label': label, 'entry': entry, 'items': item_results}
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('matrix_file', type=pathlib.Path)
    parser.add_argument('--judge-backend-env-var', default='PASCAL1981_LLM2_URL',
                         help=('Env var naming the backend base URL to use as '
                               'judge. Default: PASCAL1981_LLM2_URL. Ignored '
                               'if --skip-judge is given.'))
    parser.add_argument('--skip-judge', action='store_true',
                         help=('Collect completions (and the objective '
                               'compile-check, where available) without '
                               'calling any backend as judge -- each '
                               'candidate is left with '
                               '{"error": "judging skipped (--skip-judge)"} '
                               'in place of scores, for a human (or Claude) '
                               'to score results/*.json directly instead of '
                               'an LLM judge. The judge infrastructure '
                               '(judge_candidate, calibration) is untouched '
                               'and still available via a normal run.'))
    parser.add_argument('--port', type=int, default=8799,
                         help='Local port to run each proxy instance on.')
    parser.add_argument('--corpus-item-limit', type=int, default=None,
                         help=('Use only the first N corpus items (sorted by '
                               'id). For smoke-testing a matrix cheaply '
                               'before running it over the full corpus.'))
    args = parser.parse_args()

    matrix = load_matrix(args.matrix_file)
    corpus = load_corpus()
    if args.corpus_item_limit is not None:
        corpus = corpus[:args.corpus_item_limit]
    print(f'loaded {len(corpus)} corpus items, {len(matrix)} matrix entries',
          file=sys.stderr)

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime('%Y%m%dT%H%M%S')
    for entry in matrix:
        result = run_matrix_entry(entry, corpus, args.judge_backend_env_var,
                                   args.port, skip_judge=args.skip_judge)
        out_path = RESULTS_DIR / f'{timestamp}-{entry["label"]}.json'
        out_path.write_text(json.dumps(result, indent=2, ensure_ascii=False),
                             encoding='utf-8')
        print(f'wrote {out_path}', file=sys.stderr)


if __name__ == '__main__':
    main()
