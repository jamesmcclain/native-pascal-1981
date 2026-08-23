#!/usr/bin/env python3
"""Render tools/autoresearch/results/*.json into a markdown leaderboard
report. Pure aggregation/formatting -- does not talk to the proxy or any
LLM, so it can be re-run cheaply after tweaking only the report layout.

Usage:
    python3 tools/autoresearch/build_report.py > tools/autoresearch/REPORT.md
"""
from __future__ import annotations

import argparse
import json
import pathlib
import statistics
import sys

AUTORESEARCH_DIR = pathlib.Path(__file__).resolve().parent
RESULTS_DIR = AUTORESEARCH_DIR / 'results'
AXES = ('correctness', 'anticipation', 'efficiency', 'aesthetics')


def load_results(results_dir: pathlib.Path) -> list[dict]:
    runs = []
    for path in sorted(results_dir.glob('*.json')):
        runs.append(json.loads(path.read_text(encoding='utf-8')))
    return runs


def summarize_run(run: dict) -> dict:
    axis_scores = {axis: [] for axis in AXES}
    latencies = []
    prompt_chars = []
    compile_outcomes = []
    judge_errors = 0
    examples = {axis: [] for axis in AXES}  # (score, item_id, candidate)

    for item in run['items']:
        if 'error' in item:
            continue
        latencies.append(item['latency_seconds'])
        if 'prompt_chars' in item:
            prompt_chars.append(item['prompt_chars'])
        for cand in item['candidates']:
            compile_result = cand.get('compile_check')
            if compile_result is not None:
                compile_outcomes.append(compile_result['passed'])
            judge = cand.get('judge', {})
            if 'error' in judge:
                judge_errors += 1
                continue
            for axis in AXES:
                if axis in judge:
                    axis_scores[axis].append(judge[axis])
                    examples[axis].append(
                        (judge[axis], item['id'], cand['candidate']))

    def mean_or_none(values):
        return round(statistics.mean(values), 2) if values else None

    return {
        'label': run['label'],
        'backend': run['entry'].get('backend_env_var', '?'),
        'entry': run['entry'],
        'n_items': len(run['items']),
        'mean_latency': mean_or_none(latencies),
        'mean_prompt_chars': mean_or_none(prompt_chars),
        'compile_pass_rate': (round(sum(compile_outcomes) / len(compile_outcomes), 2)
                                if compile_outcomes else None),
        'judge_errors': judge_errors,
        'mean_scores': {axis: mean_or_none(axis_scores[axis]) for axis in AXES},
        'examples': examples,
    }


def render_leaderboard(summaries: list[dict]) -> str:
    # "backend" is its own column, not folded into "label": the label
    # names the research variant (prompt/parameter choice under study);
    # which backend happened to run it is a separate axis a matrix can
    # loop over (see load_matrix in run_experiment.py), not part of the
    # variant's identity.
    header = ('| label | backend | correctness | anticipation | efficiency '
               '| aesthetics | compile pass rate | mean latency (s) '
               '| mean prompt chars |')
    sep = '|---' * 9 + '|'
    rows = [header, sep]
    for s in summaries:
        scores = s['mean_scores']
        rows.append(
            f"| {s['label']} "
            f"| {s['backend']} "
            f"| {scores['correctness']} "
            f"| {scores['anticipation']} "
            f"| {scores['efficiency']} "
            f"| {scores['aesthetics']} "
            f"| {s['compile_pass_rate']} "
            f"| {s['mean_latency']} "
            f"| {s['mean_prompt_chars']} |")
    return '\n'.join(rows)


def render_examples(summaries: list[dict], top_n: int = 2) -> str:
    sections = []
    for s in summaries:
        lines = [f'### {s["label"]} ({s["backend"]})']
        for axis in AXES:
            scored = sorted(s['examples'][axis], key=lambda t: t[0])
            if not scored:
                continue
            worst = scored[:top_n]
            best = scored[-top_n:]
            lines.append(f'\n**{axis}** -- best:')
            for score, item_id, candidate in reversed(best):
                lines.append(f'- `{item_id}` (score {score}): '
                              f'```{candidate[:200]!r}```')
            lines.append(f'\n**{axis}** -- worst:')
            for score, item_id, candidate in worst:
                lines.append(f'- `{item_id}` (score {score}): '
                              f'```{candidate[:200]!r}```')
        sections.append('\n'.join(lines))
    return '\n\n'.join(sections)


def render_report(summaries: list[dict]) -> str:
    parts = [
        '# Autoresearch completion-quality report',
        '',
        ('Axes are 1-5, judged by an LLM per candidate (see judge_prompt.txt). '
         '"compile pass rate" is an objective, non-LLM signal available only '
         'for corpus items with `compiles_when_appended: true`. "mean prompt '
         'chars" is the exact assembled prompt size in characters (see '
         'run_experiment.py:estimate_prompt_chars) -- a token/prompt-size '
         'efficiency signal distinct from the judged "efficiency" axis, '
         'particularly relevant for small local models that a bloated '
         'prompt can overwhelm.'),
        '',
        render_leaderboard(summaries),
        '',
        '## Representative examples',
        '',
        render_examples(summaries),
    ]
    return '\n'.join(parts)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results-dir', type=pathlib.Path, default=RESULTS_DIR)
    args = parser.parse_args()

    runs = load_results(args.results_dir)
    if not runs:
        print(f'no results found under {args.results_dir}', file=sys.stderr)
        sys.exit(1)
    summaries = [summarize_run(run) for run in runs]
    print(render_report(summaries))


if __name__ == '__main__':
    main()
