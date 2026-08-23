#!/usr/bin/env python3
"""Generate the "truncated real program" bucket of the autoresearch corpus.

Reads known-good, known-compiling Pascal 1981 source files from
tests/golden/, tests/integration/, and (when present alongside this repo
checkout) ~/local/src/project-euler/problem-*/*.pas, cuts each one at a
handful of clean line-boundary split points, and emits one JSON file per
split point under tools/autoresearch/corpus/. Each emitted item's `buffer`
plus its `reference_continuation` reconstructs the source file exactly, so
the harness can objectively check "does buffer + candidate still compile"
for these items (see run_experiment.py).

This script only handles bucket 1 of the corpus (see the autoresearch plan).
Buckets 2 (hand-written micro-cases) and 3 (whole-task prompts) are
hand-written JSON files committed directly under corpus/ -- there's no
source file to derive them from, so there's nothing for a generator to do.

Re-run this script any time the source pool changes; it overwrites its own
previously generated files (identified by the `"generated": true` field) and
leaves hand-written corpus files untouched.
"""
from __future__ import annotations

import json
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
CORPUS_DIR = pathlib.Path(__file__).resolve().parent / 'corpus'

# Directories of known-good, known-compiling .pas source to draw from, with
# a glob pattern per directory. Kept narrow (golden files, the direct-host
# project-euler program per problem, and a capped sample of integration
# fixtures) rather than every .pas file in sight, since a naive rglob over
# tests/integration + all three project-euler implementation styles per
# problem balloons the corpus into the hundreds -- see the target size (~40-
# 60 items) in the autoresearch plan. The project-euler checkout is a
# sibling directory, not part of this repo, so it's fine if it's absent
# (e.g. a checkout that only has this repo).
SOURCE_GLOBS = [
    (REPO_ROOT / 'tests' / 'golden', '*.pas'),
    # Direct-host implementation only (problem_NNNN.pas) -- the glob must
    # not also match problem_NNNN_device.pas / _module.pas / _module_impl.pas
    # / _device_kernel.pas, which "problem_*.pas" would.
    (REPO_ROOT.parent / 'project-euler', 'problem-*/problem_[0-9][0-9][0-9][0-9].pas'),
]

# A hand-picked, capped sample of integration fixtures: enough to add
# variety (pointers, sets, file I/O, C FFI) without ballooning the corpus,
# since tests/integration has dozens of narrowly-scoped files.
INTEGRATION_SAMPLE = [
    'pointer_record_graph.pas',
    'file_io_basic.pas',
    'posix_file_env.pas',
    'argv_mixed_params.pas',
]

# Fraction of the way through a file's lines to place split points, chosen
# to land near natural boundaries (after a declaration block, mid-body,
# near the end) without parsing the source -- a split lands wherever the
# nearest line boundary at that fraction is, no attempt to avoid splitting
# inside a token since the split is always *between* lines.
SPLIT_FRACTIONS = [0.4, 0.75]

MIN_SOURCE_LINES = 6  # skip trivial files too short to split meaningfully
MIN_TAIL_LINES = 2    # a split must leave a non-trivial reference_continuation


def iter_source_files() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for d, pattern in SOURCE_GLOBS:
        if not d.is_dir():
            continue
        files.extend(sorted(d.glob(pattern)))
    integration_dir = REPO_ROOT / 'tests' / 'integration'
    for name in INTEGRATION_SAMPLE:
        path = integration_dir / name
        if path.is_file():
            files.append(path)
    return files


def split_points(line_count: int) -> list[int]:
    """Return distinct 1..line_count-1 line-boundary split indices."""
    points = set()
    for frac in SPLIT_FRACTIONS:
        idx = max(1, min(line_count - MIN_TAIL_LINES, round(line_count * frac)))
        points.add(idx)
    return sorted(points)


def make_item_id(source_path: pathlib.Path, split_idx: int) -> str:
    stem = source_path.stem
    return f'{stem}_split{split_idx}'


def build_item(source_path: pathlib.Path, lines: list[str],
                split_idx: int) -> dict:
    buffer = ''.join(lines[:split_idx])
    reference_continuation = ''.join(lines[split_idx:])
    cursor_line = split_idx  # 1-indexed line the cursor sits at the start of
    return {
        'id': make_item_id(source_path, split_idx),
        'goal': ('Continue this Pascal 1981 program plausibly toward a '
                 'correct, complete, idiomatic finish.'),
        'buffer': buffer,
        'cursor': {'line': cursor_line, 'column': 1},
        'reference_continuation': reference_continuation,
        'compiles_when_appended': True,
        'generated': True,
        'source_file': str(source_path.relative_to(REPO_ROOT.parent)),
    }


def generate() -> list[dict]:
    items = []
    for source_path in iter_source_files():
        text = source_path.read_text(encoding='utf-8', errors='ignore')
        lines = text.splitlines(keepends=True)
        if len(lines) < MIN_SOURCE_LINES:
            continue
        for split_idx in split_points(len(lines)):
            items.append(build_item(source_path, lines, split_idx))
    return items


def write_corpus(items: list[dict]) -> None:
    CORPUS_DIR.mkdir(parents=True, exist_ok=True)
    # Remove previously generated files so a shrinking source pool doesn't
    # leave stale items behind; hand-written files (no "generated" field,
    # or "generated": false) are left alone.
    for existing in CORPUS_DIR.glob('*.json'):
        try:
            data = json.loads(existing.read_text(encoding='utf-8'))
        except (json.JSONDecodeError, OSError):
            continue
        if data.get('generated'):
            existing.unlink()
    for item in items:
        out_path = CORPUS_DIR / f'{item["id"]}.json'
        out_path.write_text(json.dumps(item, indent=2, ensure_ascii=False) + '\n',
                             encoding='utf-8')


def main() -> None:
    items = generate()
    write_corpus(items)
    print(f'wrote {len(items)} generated corpus items to {CORPUS_DIR}',
          file=sys.stderr)


if __name__ == '__main__':
    main()
