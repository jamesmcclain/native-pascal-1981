"""Tests for the non-network logic in tools/autoresearch/run_experiment.py
and tools/autoresearch/build_report.py: report aggregation and prompt-size
estimation. Network paths (proxy subprocess, live LLM judge calls) are
exercised manually, not here -- see the autoresearch plan's Verification
section."""
import importlib.util
import pathlib
import sys
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
AUTORESEARCH_DIR = REPO_ROOT / 'tools' / 'autoresearch'


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name,
                                                  AUTORESEARCH_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


build_report = _load('build_report', 'build_report.py')
sys.path.insert(0, str(REPO_ROOT / 'tools'))
run_experiment = _load('run_experiment', 'run_experiment.py')


def _fake_run(label, item_overrides=()):
    items = [{
        'id':
        'item1',
        'latency_seconds':
        1.0,
        'prompt_chars':
        500,
        'candidates': [
            {
                'candidate': 'BEGIN END.',
                'compile_check': {
                    'passed': True
                },
                'judge': {
                    'correctness': 5,
                    'anticipation': 4,
                    'efficiency': 3,
                    'aesthetics': 5
                },
            },
            {
                'candidate': 'begin end.',
                'compile_check': {
                    'passed': False,
                    'diagnostic': 'nope'
                },
                'judge': {
                    'correctness': 2,
                    'anticipation': 2,
                    'efficiency': 2,
                    'aesthetics': 1
                },
            },
        ],
    }]
    for override in item_overrides:
        items.append(override)
    return {
        'label': label,
        'entry': {
            'label': label,
            'backend_env_var': 'ENV_A'
        },
        'items': items
    }


class SummarizeRunTests(unittest.TestCase):

    def test_mean_scores_computed_across_candidates(self):
        run = _fake_run('a')
        summary = build_report.summarize_run(run)
        self.assertEqual(summary['mean_scores']['correctness'], 3.5)
        self.assertEqual(summary['mean_scores']['aesthetics'], 3.0)

    def test_compile_pass_rate_reflects_mixed_outcomes(self):
        run = _fake_run('a')
        summary = build_report.summarize_run(run)
        self.assertEqual(summary['compile_pass_rate'], 0.5)

    def test_mean_prompt_chars_reported(self):
        run = _fake_run('a')
        summary = build_report.summarize_run(run)
        self.assertEqual(summary['mean_prompt_chars'], 500)

    def test_judge_error_excluded_from_means_and_counted(self):
        run = _fake_run('a',
                        item_overrides=[{
                            'id':
                            'item2',
                            'latency_seconds':
                            1.0,
                            'candidates': [{
                                'candidate': 'x',
                                'compile_check': None,
                                'judge': {
                                    'error': 'unparseable'
                                }
                            }],
                        }])
        summary = build_report.summarize_run(run)
        self.assertEqual(summary['judge_errors'], 1)
        # judge error candidate must not shift the correctness mean
        self.assertEqual(summary['mean_scores']['correctness'], 3.5)

    def test_item_level_error_skipped_entirely(self):
        run = _fake_run('a',
                        item_overrides=[{
                            'id': 'item2',
                            'error': 'timeout'
                        }])
        summary = build_report.summarize_run(run)
        self.assertEqual(summary['mean_scores']['correctness'], 3.5)

    def test_no_candidates_yields_none_means(self):
        run = {'label': 'empty', 'entry': {'label': 'empty'}, 'items': []}
        summary = build_report.summarize_run(run)
        self.assertIsNone(summary['mean_scores']['correctness'])
        self.assertIsNone(summary['compile_pass_rate'])


class RenderLeaderboardTests(unittest.TestCase):

    def test_leaderboard_includes_label_and_prompt_chars_column(self):
        summary = build_report.summarize_run(_fake_run('my-label'))
        table = build_report.render_leaderboard([summary])
        self.assertIn('my-label', table)
        self.assertIn('mean prompt chars', table)

    def test_leaderboard_has_a_separate_backend_column(self):
        summary = build_report.summarize_run(_fake_run('my-label'))
        table = build_report.render_leaderboard([summary])
        self.assertIn('| backend |', table)
        self.assertIn('ENV_A', table)

    def test_same_label_different_backends_both_appear_as_distinct_rows(self):
        run_a = _fake_run('baseline')
        run_b = _fake_run('baseline')
        run_b['entry']['backend_env_var'] = 'ENV_B'
        table = build_report.render_leaderboard([
            build_report.summarize_run(run_a),
            build_report.summarize_run(run_b)
        ])
        self.assertIn('ENV_A', table)
        self.assertIn('ENV_B', table)
        self.assertEqual(table.count('| baseline |'), 2)


class EstimatePromptCharsTests(unittest.TestCase):

    def test_matches_manual_build_prompt_for_n1(self):
        item = {
            'goal': 'do the thing',
            'buffer': "PROGRAM X(OUTPUT);\nBEGIN\n  WRITELN('hi')",
            'cursor': {
                'line': 3,
                'column': 15
            },
        }
        entry = {'label': 'baseline', 'proxy_args': {}}
        chars = run_experiment.estimate_prompt_chars(entry, item)

        prefix = run_experiment.proxy.compute_prefix(item['buffer'],
                                                     item['cursor']['line'],
                                                     item['cursor']['column'])
        expected_user = run_experiment.proxy.build_prompt(item['goal'], prefix)
        expected = len(run_experiment.proxy.SYSTEM_PROMPT) + len(expected_user)
        self.assertEqual(chars, expected)

    def test_grammar_file_increases_prompt_chars(self):
        item = {
            'goal': '',
            'buffer': 'PROGRAM X(OUTPUT);\nBEGIN\nEND.',
            'cursor': {
                'line': 3,
                'column': 1
            },
        }
        baseline_entry = {'label': 'baseline', 'proxy_args': {}}
        grammar_entry = {
            'label': 'grammar',
            'proxy_args': {
                '--grammar-file': 'docs/ebnf_grammar.md'
            },
        }
        baseline_chars = run_experiment.estimate_prompt_chars(
            baseline_entry, item)
        grammar_chars = run_experiment.estimate_prompt_chars(
            grammar_entry, item)
        self.assertGreater(grammar_chars, baseline_chars)


class LoadMatrixTests(unittest.TestCase):
    """The matrix format is a cross product of backends x variants (see
    load_matrix's docstring): the same variant label runs once per backend,
    and backend identity is never folded into the label."""

    def _write_matrix(self, tmp_path, data):
        import json
        p = tmp_path / 'matrix.json'
        p.write_text(json.dumps(data))
        return p

    def test_expands_to_cross_product_of_backends_and_variants(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_matrix(
                pathlib.Path(tmp), {
                    'backends': ['ENV_A', 'ENV_B'],
                    'variants': [
                        {
                            'label': 'baseline',
                            'proxy_args': {}
                        },
                        {
                            'label': 'grammar',
                            'proxy_args': {
                                '--grammar-file': 'x'
                            }
                        },
                    ],
                })
            entries = run_experiment.load_matrix(path)
        self.assertEqual(len(entries), 4)
        pairs = {(e['backend_env_var'], e['label']) for e in entries}
        self.assertEqual(
            pairs, {
                ('ENV_A', 'baseline'),
                ('ENV_A', 'grammar'),
                ('ENV_B', 'baseline'),
                ('ENV_B', 'grammar'),
            })

    def test_label_never_encodes_backend_identity(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_matrix(
                pathlib.Path(tmp), {
                    'backends': ['ENV_A', 'ENV_B'],
                    'variants': [{
                        'label': 'baseline',
                        'proxy_args': {}
                    }],
                })
            entries = run_experiment.load_matrix(path)
        labels = {e['label'] for e in entries}
        self.assertEqual(labels, {'baseline'})

    def test_variant_proxy_args_win_over_backend_override(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_matrix(
                pathlib.Path(tmp), {
                    'backends': ['ENV_A'],
                    'backend_overrides': {
                        'ENV_A': {
                            '--max-tokens': '1024'
                        }
                    },
                    'variants': [
                        {
                            'label': 'baseline',
                            'proxy_args': {}
                        },
                        {
                            'label': 'maxtokens256',
                            'proxy_args': {
                                '--max-tokens': '256'
                            }
                        },
                    ],
                })
            entries = run_experiment.load_matrix(path)
        by_label = {e['label']: e for e in entries}
        self.assertEqual(by_label['baseline']['proxy_args']['--max-tokens'],
                         '1024')
        self.assertEqual(
            by_label['maxtokens256']['proxy_args']['--max-tokens'], '256')

    def test_variant_n_defaults_to_one(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_matrix(
                pathlib.Path(tmp), {
                    'backends': ['ENV_A'],
                    'variants': [{
                        'label': 'baseline',
                        'proxy_args': {}
                    }],
                })
            entries = run_experiment.load_matrix(path)
        self.assertEqual(entries[0]['n'], 1)


if __name__ == '__main__':
    unittest.main()
