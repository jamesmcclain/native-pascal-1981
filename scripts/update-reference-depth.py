#!/usr/bin/env python3
"""Regenerate oversized AST inputs for native depth-guard tests."""

import sys
from pathlib import Path

from pascal1981 import serialization
from pascal1981.lexer import lex_file
from pascal1981.parser import Parser
from pascal1981.type_checker import PascalTypeChecker

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tests" / "reference" / "depth"


def nested_binops(depth: int) -> str:
    expression = "+(".join(["1"] * (depth + 1)) + ")" * depth
    return f"PROGRAM D;\nVAR a: INTEGER;\nBEGIN\n  a := {expression};\nEND.\n"


def nested_statements(depth: int) -> str:
    lines = ["PROGRAM S;", "VAR a: INTEGER;", "BEGIN", "  a := 0;"]
    lines += [f"  IF a = {index} THEN a := 1 ELSE" for index in range(depth)]
    lines += ["  a := 2;", "END."]
    return "\n".join(lines) + "\n"


def parse_without_limits(source: Path):
    parser = Parser(lex_file(str(source)))
    parser._expr_depth.limit = 10**9
    parser._stmt_depth.limit = 10**9
    return parser.parse()


def update(name: str, text: str) -> None:
    source = OUTPUT / f"{name}.pas"
    untyped = OUTPUT / f"{name}.ast.json"
    typed = OUTPUT / f"{name}.typed.json"
    source.write_text(text)

    ast = parse_without_limits(source)
    untyped.write_text(serialization.ast_to_json(ast))

    checker = PascalTypeChecker()
    checker._expr_depth.limit = 10**9
    checker._stmt_depth.limit = 10**9
    result = checker.check(ast)
    if not result.success:
        raise RuntimeError(f"reference typecheck failed for {name}: {result.errors}")
    typed.write_text(serialization.ast_to_json(ast))
    print(f"updated: {name}")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    previous_limit = sys.getrecursionlimit()
    sys.setrecursionlimit(100000)
    try:
        update("expr_depth_192", nested_binops(192))
        update("stmt_depth_512", nested_statements(512))
    finally:
        sys.setrecursionlimit(previous_limit)


if __name__ == "__main__":
    main()
