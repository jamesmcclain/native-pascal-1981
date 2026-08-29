"""Tests for build_corpus.py's split-point/reconstruction logic, and a shape
check over the committed corpus (generated + hand-written).

The reconstruction test is the one that matters: a generated item was made by
cutting a compiling program at a line boundary, so its buffer plus its recorded
continuation must be that program again, byte for byte. corpus_smoke.py
--reference relies on exactly that property to compile the corpus without a
model, and this is what keeps it true."""
import importlib.util
import json
import pathlib
import sys
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
HERE = pathlib.Path(__file__).resolve().parent
CORPUS_DIR = HERE / 'corpus'

spec = importlib.util.spec_from_file_location('build_corpus',
                                              HERE / 'build_corpus.py')
build_corpus = importlib.util.module_from_spec(spec)
sys.modules['build_corpus'] = build_corpus
spec.loader.exec_module(build_corpus)


class SplitPointsTests(unittest.TestCase):

    def test_split_points_are_within_bounds_and_leave_a_tail(self):
        for line_count in (6, 10, 20, 50):
            points = build_corpus.split_points(line_count)
            for p in points:
                self.assertGreaterEqual(p, 1)
                self.assertLessEqual(p,
                                     line_count - build_corpus.MIN_TAIL_LINES)

    def test_split_points_are_sorted_and_distinct(self):
        points = build_corpus.split_points(30)
        self.assertEqual(points, sorted(set(points)))


class BuildItemTests(unittest.TestCase):

    def test_buffer_plus_reference_continuation_reconstructs_source(self):
        lines = [
            'PROGRAM X(OUTPUT);\n', 'BEGIN\n', "  WRITELN('hi')\n", 'END.\n'
        ]
        item = build_corpus.build_item(REPO_ROOT / 'x.pas', lines, 2)
        reconstructed = item['buffer'] + item['reference_continuation']
        self.assertEqual(reconstructed, ''.join(lines))

    def test_item_has_expected_shape(self):
        lines = [
            'PROGRAM X(OUTPUT);\n', 'BEGIN\n', "  WRITELN('hi')\n", 'END.\n'
        ]
        item = build_corpus.build_item(REPO_ROOT / 'x.pas', lines, 2)
        self.assertEqual(item['id'], 'x_split2')
        self.assertEqual(item['cursor'], {'line': 2, 'column': 1})
        self.assertTrue(item['compiles_when_appended'])
        self.assertTrue(item['generated'])


class CommittedCorpusShapeTests(unittest.TestCase):
    """Sanity-checks the corpus actually committed under corpus/, not just
    the generator's unit-level behavior."""

    def test_corpus_directory_is_non_trivial_and_bounded(self):
        paths = list(CORPUS_DIR.glob('*.json'))
        self.assertGreater(len(paths), 20)
        self.assertLess(len(paths), 150)

    def test_every_corpus_item_has_required_fields(self):
        required = {
            'id', 'goal', 'buffer', 'cursor', 'reference_continuation',
            'compiles_when_appended'
        }
        for path in CORPUS_DIR.glob('*.json'):
            with self.subTest(path=path.name):
                item = json.loads(path.read_text(encoding='utf-8'))
                self.assertTrue(required.issubset(item.keys()))
                self.assertIn('line', item['cursor'])
                self.assertIn('column', item['cursor'])

    def test_generated_items_reconstruct_their_source_exactly(self):
        for path in CORPUS_DIR.glob('*.json'):
            item = json.loads(path.read_text(encoding='utf-8'))
            if not item.get('generated'):
                continue
            with self.subTest(path=path.name):
                source_path = REPO_ROOT.parent / item['source_file']
                if not source_path.is_file():
                    self.skipTest(f'source file not present: {source_path}')
                original = source_path.read_text(encoding='utf-8',
                                                 errors='ignore')
                reconstructed = item['buffer'] + item['reference_continuation']
                self.assertEqual(reconstructed, original)


if __name__ == '__main__':
    unittest.main()
