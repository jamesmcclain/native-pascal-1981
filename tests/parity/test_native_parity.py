"""Native compiler stages must agree with the Python reference pipeline.

Set all four variables below to executable native stage binaries to enable this
suite.  It deliberately does not build them: selecting a bootstrap artifact is
a caller/CI concern, and an ordinary test run must remain self-contained.

    NATIVE_LEXER, NATIVE_PARSER, NATIVE_TYPECHECKER, NATIVE_CODEGEN

The stages use the stdin/stdout JSON protocol.  JSON is compared as decoded
objects because the native cJSON serializer intentionally has different
whitespace.  ``resolved_type`` is stripped from typed ASTs because it is an
output-only annotation with an intentionally different native policy.  LLVM
text is not compared: independent lowerers legitimately choose different
names and orderings, so both outputs are assembled by clang instead.
"""

import json
import os
import resource
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tests.support import RUNTIME_LIB

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tests" / "fixtures"
NATIVE_ENV = {
    "lexer": "NATIVE_LEXER",
    "parser": "NATIVE_PARSER",
    "typechecker": "NATIVE_TYPECHECKER",
    "codegen": "NATIVE_CODEGEN",
}
NATIVE = {
    stage: os.environ.get(env, str(ROOT / "bin" / stage))
    for stage, env in NATIVE_ENV.items()
}
HAS_NATIVE_PIPELINE = all(path and os.access(path, os.X_OK)
                          for path in NATIVE.values())


def _run(command, stdin="", cwd=ROOT):
    """Run one pipeline stage and retain stderr for useful parity failures."""
    return subprocess.run(
        command,
        input=stdin,
        cwd=cwd,
        text=True,
        capture_output=True,
        timeout=30,
    )


def _python_pipeline(source, stages, cwd=ROOT):
    """Run the reference stages with precisely the stdin/stdout stage protocol."""
    result = _run([sys.executable, "-m", "pascal1981.cli_lex",
                   str(source)],
                  cwd=cwd)
    if result.returncode or stages == 1:
        return result
    result = _run([
        sys.executable,
        "-m",
        "pascal1981.cli_parse",
        "--source-file",
        str(source),
        "--dialect",
        "extended",
    ], result.stdout, cwd)
    if result.returncode or stages == 2:
        return result
    result = _run([
        sys.executable,
        "-m",
        "pascal1981.cli_typecheck",
        "--source-file",
        str(source),
        "--dialect",
        "extended",
    ], result.stdout, cwd)
    if result.returncode or stages == 3:
        return result
    return _run([
        sys.executable,
        "-m",
        "pascal1981.cli_codegen",
        "--source-file",
        str(source),
        "--dialect",
        "extended",
    ], result.stdout, cwd)


def _native_pipeline(source, stages, cwd=ROOT):
    """Run native stages, feeding each stage's stdout into the next one."""
    result = _run([NATIVE["lexer"]], source.read_text(), cwd)
    for stage in ("parser", "typechecker", "codegen")[:stages - 1]:
        if result.returncode:
            return result
        result = _run([NATIVE[stage]], result.stdout, cwd)
    return result


def _without_resolved_type(value):
    """Remove the known non-semantic typed-AST annotation recursively."""
    if isinstance(value, list):
        return [_without_resolved_type(item) for item in value]
    if isinstance(value, dict):
        return {
            key: _without_resolved_type(item)
            for key, item in value.items() if key != "resolved_type"
        }
    return value


@unittest.skipUnless(
    HAS_NATIVE_PIPELINE,
    "requires executable NATIVE_LEXER, NATIVE_PARSER, NATIVE_TYPECHECKER, and NATIVE_CODEGEN",
)
class TestNativeFixtureParity(unittest.TestCase):
    """Exercise every single-file parser/typecheck fixture in both pipelines."""

    def _assert_json_equal(self,
                           source,
                           stages,
                           normalizer=lambda value: value,
                           cwd=ROOT):
        python = _python_pipeline(source, stages, cwd)
        native = _native_pipeline(source, stages, cwd)
        self.assertEqual(python.returncode, 0,
                         f"Python rejected {source}:\n{python.stderr}")
        self.assertEqual(native.returncode, 0,
                         f"Native rejected {source}:\n{native.stderr}")
        try:
            expected = normalizer(json.loads(python.stdout))
            actual = normalizer(json.loads(native.stdout))
        except json.JSONDecodeError as exc:
            self.fail(
                f"{source}: stage {stages} did not emit JSON: {exc}\nNative stderr:\n{native.stderr}"
            )
        self.assertEqual(actual, expected,
                         f"native/Python JSON mismatch for {source}")

    def _assert_same_acceptance(self, source, stages):
        python = _python_pipeline(source, stages)
        native = _native_pipeline(source, stages)
        self.assertEqual(
            native.returncode == 0,
            python.returncode == 0,
            f"native/Python acceptance differs for {source}\n"
            f"Python stderr:\n{python.stderr}\nNative stderr:\n{native.stderr}",
        )

    def test_parser_success_fixtures_have_equal_ast(self):
        for source in sorted(
            (FIXTURES / "parser" / "should_pass").glob("*.pas")):
            with self.subTest(source=source.name):
                self._assert_json_equal(source, stages=2)

    def test_parser_failure_fixtures_have_same_acceptance(self):
        for source in sorted(
            (FIXTURES / "parser" / "should_fail").glob("*.pas")):
            with self.subTest(source=source.name):
                self._assert_same_acceptance(source, stages=2)

    def test_stray_rparen_parser_failure_is_bounded(self):
        source = (FIXTURES / "parser" / "should_fail" /
                  "16_stray_rparen_in_compound.pas")
        lexed = _run([NATIVE["lexer"]], source.read_text())
        self.assertEqual(lexed.returncode, 0, lexed.stderr)

        memory_limit = 128 * 1024 * 1024

        def limit_address_space():
            resource.setrlimit(resource.RLIMIT_AS,
                               (memory_limit, memory_limit))

        parsed = subprocess.run(
            [NATIVE["parser"]],
            input=lexed.stdout,
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=5,
            preexec_fn=limit_address_space,
        )
        self.assertNotEqual(parsed.returncode, 0)
        self.assertIn("Parser Error: expected statement", parsed.stderr)

    def test_parser_judgment_call_fixtures_have_expected_parity(self):
        fixtures = FIXTURES / "parser" / "judgment_calls"
        self._assert_json_equal(fixtures / "A_write_field_width.pas", stages=2)
        self._assert_same_acceptance(fixtures / "B_colon_args_any_call.pas",
                                     stages=2)

    def test_typecheck_success_fixtures_have_equal_typed_ast(self):
        for source in sorted(
            (FIXTURES / "typecheck" / "should_pass").glob("*.pas")):
            with self.subTest(source=source.name):
                self._assert_json_equal(source,
                                        stages=3,
                                        normalizer=_without_resolved_type)

    def test_typecheck_failure_fixtures_have_same_acceptance(self):
        for source in sorted(
            (FIXTURES / "typecheck" / "should_fail").glob("*.pas")):
            with self.subTest(source=source.name):
                self._assert_same_acceptance(source, stages=3)

    def test_self_hosting_sources_have_canonical_stage_output(self):
        """Diff the shared self-hosting sources without comparing LLVM text."""
        for name in ("lexer.pas", "parser.pas", "typechecker.pas",
                     "codegen.pas", "jsonutil.pas"):
            source = ROOT / "src" / name
            with self.subTest(source=name, stage="parser"):
                self._assert_json_equal(source, stages=2, cwd=source.parent)
            with self.subTest(source=name, stage="typechecker"):
                self._assert_json_equal(source,
                                        stages=3,
                                        normalizer=_without_resolved_type,
                                        cwd=source.parent)
            with self.subTest(source=name, stage="codegen"):
                for label, result in (("Python",
                                       _python_pipeline(
                                           source, 4, source.parent)),
                                      ("native",
                                       _native_pipeline(
                                           source, 4, source.parent))):
                    self.assertEqual(
                        result.returncode, 0,
                        f"{label} codegen rejected {source}:\n{result.stderr}")
                    assembled = _run(
                        ["clang", "-x", "ir", "-c", "-o", os.devnull, "-"],
                        result.stdout)
                    self.assertEqual(
                        assembled.returncode, 0,
                        f"{label} emitted invalid LLVM for {source}:\n{assembled.stderr}"
                    )

    @unittest.skipUnless(shutil.which("clang"),
                         "requires clang to verify LLVM assembly")
    def test_typecheck_success_fixtures_emit_valid_llvm(self):
        for source in sorted(
            (FIXTURES / "typecheck" / "should_pass").glob("*.pas")):
            with self.subTest(source=source.name):
                python = _python_pipeline(source, stages=4)
                native = _native_pipeline(source, stages=4)
                self.assertEqual(
                    python.returncode, 0,
                    f"Python codegen rejected {source}:\n{python.stderr}")
                self.assertEqual(
                    native.returncode, 0,
                    f"Native codegen rejected {source}:\n{native.stderr}")
                for label, result in (("Python", python), ("native", native)):
                    assembled = _run(
                        ["clang", "-x", "ir", "-c", "-o", os.devnull, "-"],
                        result.stdout)
                    self.assertEqual(
                        assembled.returncode, 0,
                        f"{label} emitted invalid LLVM for {source}:\n{assembled.stderr}"
                    )

    def test_depth_ceilings_have_the_same_boundary(self):
        """Both parsers must accept and reject at exactly the same depth.

        tests/test_depth_limits.py pins the two ceilings to the same numbers by
        reading the constants out of the .pas sources, but equal constants are
        not the same thing as equal behavior: an off-by-one in where either
        parser increments would leave the compilers accepting different
        languages while both files still read 64 and 256.  Only running the two
        parsers against the boundary settles it.
        """
        from pascal1981.depth_limits import MAX_EXPR_DEPTH, MAX_STMT_DEPTH

        from tests.parity.test_depth_limits import (nested_else_if,
                                                    nested_parens)

        cases = []
        for offset in (-1, 0):
            cases.append((f"expr{MAX_EXPR_DEPTH + offset}",
                          nested_parens(MAX_EXPR_DEPTH + offset)))
            cases.append((f"stmt{MAX_STMT_DEPTH + offset}",
                          nested_else_if(MAX_STMT_DEPTH + offset)))

        with tempfile.TemporaryDirectory() as work:
            for label, text in cases:
                with self.subTest(case=label):
                    source = Path(work) / f"{label}.pas"
                    source.write_text(text)
                    self._assert_same_acceptance(source, stages=2)


def _link_and_run(ir_text, exe_name):
    """Link LLVM IR against the Pascal runtime and run it.

    Returns (returncode, stdout, stderr).  This is the gate LLVMVerifyModule
    cannot be: a module can verify clean and still miscompile (the §1.1
    by-value-aggregate ABI bug and the malloc.1 uniquification bug were both
    verifier-clean but wrong), so native codegen output is only trusted once
    it links and runs the way the Python reference does.
    """
    with tempfile.TemporaryDirectory() as work:
        ll_path = os.path.join(work, "p.ll")
        with open(ll_path, "w") as handle:
            handle.write(ir_text)
        exe_path = os.path.join(work, exe_name)
        link = _run(["clang", ll_path, RUNTIME_LIB, "-o", exe_path])
        if link.returncode:
            return link.returncode, "", link.stderr
        run = _run([exe_path])
        return run.returncode, run.stdout, run.stderr


@unittest.skipUnless(
    HAS_NATIVE_PIPELINE and shutil.which("clang"),
    "requires the native pipeline + clang to link and run",
)
class TestNativeLinkAndRun(unittest.TestCase):
    """Native codegen output must link and run, not merely assemble.

    ``test_typecheck_success_fixtures_emit_valid_llvm`` above stops at
    ``clang -x ir -c`` (assemble-only), which proves the IR is well-formed but
    nothing about its behavior.  This class links a program exercising the
    codegen paths most likely to be 'verifier-clean but wrong' -- by-value
    aggregate parameters (the §1.1 ABI danger zone), record/array access,
    loops, mixed REAL/INTEGER arithmetic, and function calls -- against the
    real Pascal runtime, runs it, and requires the native stdout to match the
    Python reference's stdout byte-for-byte.  It is the runtime enforcement
    the §1.6 checklist item calls for; any codegen change that breaks
    link-and-run now fails here rather than slipping past the verifier.
    """

    _PROGRAM = (
        "PROGRAM P(output);\n"
        "TYPE\n"
        "  Str255 = LSTRING(255);\n"
        "  Rec = RECORD a: INTEGER32; b: REAL; c: ARRAY[0..3] OF INTEGER32 END;\n"
        "VAR r: Rec; i: INTEGER; sum: INTEGER32;\n"
        "FUNCTION firstch(s: Str255): CHAR;\n"
        "BEGIN firstch := s[1] END;\n"
        "FUNCTION double(x: INTEGER32): INTEGER32;\n"
        "BEGIN double := x * 2 END;\n"
        "BEGIN\n"
        "  r.a := 41; r.b := 3.14; r.c[0] := 1; r.c[1] := 2; r.c[2] := 4; r.c[3] := 8;\n"
        "  r.a := double(r.a + 1);\n"
        "  sum := 0;\n"
        "  FOR i := 0 TO 3 DO sum := sum + r.c[i];\n"
        "  WRITELN(r.a);\n"
        "  WRITELN(r.b);\n"
        "  WRITELN(sum);\n"
        "  WRITELN(firstch('hello'))\n"
        "END.\n")

    def test_native_codegen_output_links_and_runs_matching_python(self):
        with tempfile.NamedTemporaryFile("w", suffix=".pas",
                                         delete=False) as handle:
            handle.write(self._PROGRAM)
            source = Path(handle.name)
        try:
            python = _python_pipeline(source, stages=4)
            native = _native_pipeline(source, stages=4)
            self.assertEqual(
                python.returncode, 0,
                f"Python codegen rejected the program:\n{python.stderr}")
            self.assertEqual(
                native.returncode, 0,
                f"Native codegen rejected the program:\n{native.stderr}")
            py_rc, py_out, py_err = _link_and_run(python.stdout, "py-prog")
            self.assertEqual(py_rc, 0,
                             f"Python IR failed to link/run:\n{py_err}")
            nat_rc, nat_out, nat_err = _link_and_run(native.stdout, "nat-prog")
            self.assertEqual(nat_rc, 0,
                             f"Native IR failed to link/run:\n{nat_err}")
            self.assertEqual(
                nat_out, py_out,
                f"native/Python link-and-run output mismatch:\n"
                f"--- native ---\n{nat_out}\n--- python ---\n{py_out}")
        finally:
            os.unlink(source)


if __name__ == "__main__":
    unittest.main()
