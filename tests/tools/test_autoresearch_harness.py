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
    return {'label': label, 'entry': {'label': label}, 'items': items}


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
        n = 1
        chars = run_experiment.estimate_prompt_chars(entry, item, n)

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
            baseline_entry, item, 1)
        grammar_chars = run_experiment.estimate_prompt_chars(
            grammar_entry, item, 1)
        self.assertGreater(grammar_chars, baseline_chars)

    def test_multi_candidate_prompt_chars_use_multi_templates(self):
        item = {
            'goal': '',
            'buffer': 'PROGRAM X(OUTPUT);\nBEGIN\nEND.',
            'cursor': {
                'line': 3,
                'column': 1
            },
        }
        entry = {'label': 'baseline', 'proxy_args': {}}
        n1_chars = run_experiment.estimate_prompt_chars(entry, item, 1)
        n3_chars = run_experiment.estimate_prompt_chars(entry, item, 3)
        self.assertNotEqual(n1_chars, n3_chars)


if __name__ == '__main__':
    unittest.main()
