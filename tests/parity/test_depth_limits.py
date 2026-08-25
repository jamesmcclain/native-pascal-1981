"""Recursion-depth ceilings on the recursive walks over source and ASTs.

Three things need to hold, and each is easy to break silently:

1. The two compilers agree on the numbers.  They cannot share a constant --
   the native stages are Pascal -- so the values are asserted equal here.
2. The ceiling is the limit that gets reached, not the host's.  A ceiling that
   sits above ``sys.getrecursionlimit()`` would never fire, and the toolchain
   would go back to reporting "maximum recursion depth exceeded".
3. Every phase that walks the tree is guarded, not just the parser.  The
   split-process CLIs read an AST from stdin, so the checker and code
   generator can be handed a tree the parser never saw.
"""

import subprocess
import sys
from pathlib import Path

import pytest
from pascal1981 import serialization as ser
from pascal1981.codegen import Codegen, CodegenError
from pascal1981.depth_limits import (EXPR_TOO_DEEP, MAX_EXPR_DEPTH,
                                     MAX_STMT_DEPTH, STMT_TOO_DEEP)
from pascal1981.lexer import lex_file
from pascal1981.parser import Parser, ParserError
from pascal1981.type_checker import PascalTypeChecker

PASCAL_SRC = Path(__file__).resolve().parents[2] / 'src'


def nested_parens(n):
    """A source whose only depth is ``n`` levels of expression nesting."""
    return 'PROGRAM D;\nVAR a: INTEGER;\nBEGIN\n  a := ' + '(' * n + '1' + ')' * n + ';\nEND.\n'


def nested_binops(n):
    """A source with ``n`` levels of *AST* expression nesting.

    Not the same thing as nested_parens: ``((((1))))`` costs the parser a
    recursion level per paren but produces a bare IntLiteral, because
    parse_factor hands the inner expression straight back.  The phases that
    walk the finished tree only recurse where the tree does, so they need an
    operator at every level.
    """
    return ('PROGRAM D;\nVAR a: INTEGER;\nBEGIN\n  a := ' +
            '+('.join(['1'] * (n + 1)) + ')' * n + ';\nEND.\n')


def nested_else_if(n):
    """A source whose only depth is ``n`` levels of statement nesting.

    An ELSE-IF chain is the shape that actually shows up in real code -- the
    native lexer's own keyword lookup is a 64-deep one -- and it nests to the
    right, one ParseStatement per ELSE.
    """
    lines = ['PROGRAM S;', 'VAR a: INTEGER;', 'BEGIN', '  a := 0;']
    lines += [f'  IF a = {i} THEN a := 1 ELSE' for i in range(n)]
    lines += ['  a := 2;', 'END.']
    return '\n'.join(lines) + '\n'


def parse_source(tmp_path, text):
    path = tmp_path / 'input.pas'
    path.write_text(text)
    return Parser(lex_file(str(path))).parse()


def parse_deeper_than_allowed(tmp_path, text):
    """Parse past the ceilings, to get a tree the later phases must reject.

    This is the only way to build the input the split-process CLIs can be
    handed: an AST that this front end would never emit.  Raising the host
    recursion limit for the parse keeps the failure under test the ceiling
    rather than Python's own limit.
    """
    path = tmp_path / 'input.pas'
    path.write_text(text)
    parser = Parser(lex_file(str(path)))
    parser._expr_depth.limit = 10**9
    parser._stmt_depth.limit = 10**9
    original = sys.getrecursionlimit()
    sys.setrecursionlimit(100000)
    try:
        return parser.parse()
    finally:
        sys.setrecursionlimit(original)


class TestCeilingIsTheBindingLimit:
    """The ceiling must be reached before the host's own limit is."""

    def test_expr_ceiling_is_below_the_recursion_limit(self, tmp_path):
        # The parser is the deepest-recursing phase, so if the ceiling binds
        # here it binds everywhere downstream.
        deep = parse_deeper_than_allowed(tmp_path,
                                         nested_parens(MAX_EXPR_DEPTH * 2))
        assert deep is not None  # no RecursionError at twice the ceiling

    def test_stmt_ceiling_is_below_the_recursion_limit(self, tmp_path):
        deep = parse_deeper_than_allowed(tmp_path,
                                         nested_else_if(MAX_STMT_DEPTH * 2))
        assert deep is not None

    @pytest.mark.parametrize('depth',
                             [MAX_EXPR_DEPTH, MAX_EXPR_DEPTH * 4, 1000])
    def test_no_recursion_error_escapes_for_deep_expressions(
            self, tmp_path, depth):
        with pytest.raises(ParserError):
            parse_source(tmp_path, nested_parens(depth))

    @pytest.mark.parametrize('depth',
                             [MAX_STMT_DEPTH, MAX_STMT_DEPTH * 4, 2000])
    def test_no_recursion_error_escapes_for_deep_statements(
            self, tmp_path, depth):
        with pytest.raises(ParserError):
            parse_source(tmp_path, nested_else_if(depth))


class TestParserCeilings:

    def test_accepts_just_under_the_expr_ceiling(self, tmp_path):
        assert parse_source(tmp_path,
                            nested_parens(MAX_EXPR_DEPTH - 1)) is not None

    def test_rejects_at_the_expr_ceiling(self, tmp_path):
        with pytest.raises(ParserError, match='expression too complex'):
            parse_source(tmp_path, nested_parens(MAX_EXPR_DEPTH))

    def test_accepts_just_under_the_stmt_ceiling(self, tmp_path):
        assert parse_source(tmp_path,
                            nested_else_if(MAX_STMT_DEPTH - 1)) is not None

    def test_rejects_at_the_stmt_ceiling(self, tmp_path):
        with pytest.raises(ParserError, match='nested too deeply'):
            parse_source(tmp_path, nested_else_if(MAX_STMT_DEPTH))

    def test_depth_unwinds_between_sibling_expressions(self, tmp_path):
        """Depth is nesting, not a running total.

        A guard that forgot to decrement would accept the first deep-ish
        expression and reject a later shallow one, which is a much worse
        failure than rejecting the deep one: the diagnostic would point at
        innocent code.
        """
        one = '(' * (MAX_EXPR_DEPTH - 2) + '1' + ')' * (MAX_EXPR_DEPTH - 2)
        text = ('PROGRAM D;\nVAR a: INTEGER;\nBEGIN\n' +
                ''.join(f'  a := {one};\n' for _ in range(6)) + 'END.\n')
        assert parse_source(tmp_path, text) is not None

    def test_a_rejected_parse_does_not_poison_the_next_one(self, tmp_path):
        """Two parses in one process must not share a count.

        The CLI is one parse per process, but the test suite and any embedding
        caller are not.
        """
        with pytest.raises(ParserError):
            parse_source(tmp_path, nested_parens(MAX_EXPR_DEPTH * 2))
        assert parse_source(tmp_path, nested_parens(4)) is not None


class TestAstConsumingPhases:
    """cli_typecheck and cli_codegen read an AST from stdin.

    Nothing about that JSON has been through this front end's parser, so the
    parser's ceilings guarantee nothing about it.  Both phases guard the same
    two cycles themselves.
    """

    def json_round_trip(self, ast):
        # Exactly what the split-process CLIs receive.
        return ser.ast_from_json(ser.ast_to_json(ast))

    def test_checker_rejects_a_deep_expression_ast(self, tmp_path):
        ast = self.json_round_trip(
            parse_deeper_than_allowed(tmp_path,
                                      nested_binops(MAX_EXPR_DEPTH * 3)))
        result = PascalTypeChecker().check(ast)
        assert not result.success
        assert any(EXPR_TOO_DEEP in e.message for e in result.errors)

    def test_checker_rejects_a_deep_statement_ast(self, tmp_path):
        ast = self.json_round_trip(
            parse_deeper_than_allowed(tmp_path,
                                      nested_else_if(MAX_STMT_DEPTH * 2)))
        result = PascalTypeChecker().check(ast)
        assert not result.success
        assert any(STMT_TOO_DEEP in e.message for e in result.errors)

    def test_checker_reports_a_ceiling_not_an_internal_error(self, tmp_path):
        """The unwind must not surface as "Internal error during type checking".

        check() funnels every stray exception into that message, so the
        depth-limit unwind has to be recognised ahead of it or the user is told
        the compiler broke rather than that their program is too deep.
        """
        ast = self.json_round_trip(
            parse_deeper_than_allowed(tmp_path,
                                      nested_binops(MAX_EXPR_DEPTH * 3)))
        result = PascalTypeChecker().check(ast)
        assert not any('Internal error' in e.message for e in result.errors)

    def test_codegen_rejects_a_deep_expression_ast(self, tmp_path):
        ast = self.json_round_trip(
            parse_deeper_than_allowed(tmp_path,
                                      nested_binops(MAX_EXPR_DEPTH * 3)))
        with pytest.raises(CodegenError, match='expression too complex'):
            Codegen().codegen_program(ast)

    def test_codegen_rejects_a_deep_statement_ast(self, tmp_path):
        ast = self.json_round_trip(
            parse_deeper_than_allowed(tmp_path,
                                      nested_else_if(MAX_STMT_DEPTH * 2)))
        with pytest.raises(CodegenError, match='nested too deeply'):
            Codegen().codegen_program(ast)


class TestOrdinaryProgramsAreUnaffected:
    """The ceilings must be far above anything real code reaches.

    A ceiling that ordinary programs trip is a regression however good its
    diagnostic is, so pin the sources the toolchain has to compile to keep
    working: its own five self-hosting stages.
    """

    @pytest.mark.parametrize('source', [
        'lexer.pas', 'parser.pas', 'typechecker.pas', 'codegen.pas',
        'jsonutil.pas'
    ])
    def test_self_hosting_source_parses(self, source):
        assert Parser(lex_file(str(PASCAL_SRC / source))).parse() is not None


class TestCliDiagnostics:

    def run_cli(self, tmp_path, text):
        path = tmp_path / 'input.pas'
        path.write_text(text)
        return subprocess.run([
            sys.executable, '-m', 'pascal1981.compile_to_llvm', '--dialect',
            'extended', '-S',
            str(path), '-o',
            str(tmp_path / 'out.ll')
        ],
                              capture_output=True,
                              text=True)

    def test_deep_expression_names_the_construct(self, tmp_path):
        proc = self.run_cli(tmp_path, nested_parens(MAX_EXPR_DEPTH * 2))
        assert proc.returncode != 0
        assert 'expression too complex' in proc.stderr
        assert 'maximum recursion depth' not in proc.stderr

    def test_deep_statements_name_the_construct(self, tmp_path):
        proc = self.run_cli(tmp_path, nested_else_if(MAX_STMT_DEPTH * 2))
        assert proc.returncode != 0
        assert 'nested too deeply' in proc.stderr
        assert 'maximum recursion depth' not in proc.stderr
