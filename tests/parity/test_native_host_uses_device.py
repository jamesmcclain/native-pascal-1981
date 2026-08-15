"""A host compiland that USES a DEVICE INTERFACE, lowered by native codegen.

The interface is spliced into the host source by $INCLUDE, so its declarations
reach codegen as local_interfaces.  They must be lowered in device context --
an ADS(GLOBAL) OF T parameter is legal there and nowhere else -- while the host
compiland itself stays a host compiland.

Set NATIVE_CODEGEN to a native codegen.pas executable.  The Python front end
supplies the normal typed-AST JSON protocol; this test isolates native
lowering.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NATIVE_CODEGEN = os.environ.get("NATIVE_CODEGEN",
                                str(ROOT / "bin" / "codegen"))

_INTERFACE = """\
DEVICE INTERFACE;
UNIT bumpu (bump);
PROCEDURE bump(p: ADS(GLOBAL) OF INTEGER32; step: INTEGER32);
END;
"""

_IMPLEMENTATION = """\
(*$INCLUDE:'bump.inc'*)
DEVICE IMPLEMENTATION OF bumpu;
PROCEDURE bump(p: ADS(GLOBAL) OF INTEGER32; step: INTEGER32);
BEGIN
  p^ := p^ + step
END;
.
"""

# The host never names ADS: it hands the kernel one of its own `^INTEGER32`
# heap pointers, which is what the reference type system's plain-pointer
# wildcard allows.
_HOST = """\
(*$INCLUDE:'bump.inc'*)
PROGRAM host(output);
USES bumpu (bump);
TYPE PINT = ^INTEGER32;
VAR p: PINT;
BEGIN
  NEW(p);
  p^ := 0;
  LAUNCH(bump, 2, 3, p, 1);
  WRITELN(p^);
  DISPOSE(p)
END.
"""


def _typed_ast(source: Path) -> str:
    lex = subprocess.run(
        [sys.executable, "-m", "pascal1981.cli_lex",
         str(source)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    parse = subprocess.run(
        [
            sys.executable, "-m", "pascal1981.cli_parse", "--source-file",
            str(source), "--dialect", "extended"
        ],
        cwd=ROOT,
        input=lex.stdout,
        text=True,
        capture_output=True,
        check=True,
    )
    checked = subprocess.run(
        [
            sys.executable, "-m", "pascal1981.cli_typecheck", "--source-file",
            str(source), "--dialect", "extended"
        ],
        cwd=ROOT,
        input=parse.stdout,
        text=True,
        capture_output=True,
        check=True,
    )
    return checked.stdout


def _project(directory: Path, host_source: str = _HOST) -> None:
    (directory / "bump.inc").write_text(_INTERFACE)
    (directory / "bump.pas").write_text(_IMPLEMENTATION)
    (directory / "host.pas").write_text(host_source)


@unittest.skipUnless(NATIVE_CODEGEN and os.access(NATIVE_CODEGEN, os.X_OK),
                     "requires NATIVE_CODEGEN")
class HostUsesDeviceInterfaceTests(unittest.TestCase):

    def _codegen(self, source: Path, expect_success: bool = True):
        result = subprocess.run(
            [NATIVE_CODEGEN],
            cwd=ROOT,
            input=_typed_ast(source),
            text=True,
            capture_output=True,
        )
        if expect_success:
            self.assertEqual(result.returncode, 0,
                             result.stderr + result.stdout)
        return result

    def test_host_declares_the_kernel_and_reaches_it_only_through_the_thunk(
            self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            _project(work)
            ir = self._codegen(work / "host.pas").stdout
        # The imported kernel is an external declaration with the device
        # unit's own ABI; on the CPU device that is a flat pointer.
        self.assertIn("declare void @bump(ptr, i32)", ir)
        # ...and the host reaches it the way every LAUNCH does.
        self.assertIn("define internal void @__pas_klaunch_bump(", ir)
        self.assertEqual(ir.count("call void @bump("), 1)
        self.assertIn("@pas_dev_launch", ir)

    def test_host_and_kernel_link_and_run(self):
        runtime_lib = ROOT / "runtime" / "build" / "libpascalrt.a"
        if not runtime_lib.exists():
            subprocess.run(["make", "-C", str(ROOT / "runtime")],
                           check=True,
                           capture_output=True)
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            _project(work)
            (work / "host.ll").write_text(
                self._codegen(work / "host.pas").stdout)
            (work / "bump.ll").write_text(
                self._codegen(work / "bump.pas").stdout)
            exe = work / "host"
            link = subprocess.run(
                [
                    "clang",
                    str(work / "host.ll"),
                    str(work / "bump.ll"),
                    str(runtime_lib), "-lm", "-o",
                    str(exe)
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(link.returncode, 0, link.stderr)
            run = subprocess.run([str(exe)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        # A grid of 2 blocks x 3 threads, each adding 1 to the same cell.
        self.assertEqual(run.stdout.split(), ["6"])

    # The three cases below cannot be written in source: the type checker
    # rejects each one first, with its own equivalent message.  Native codegen
    # still has to hold the line, because it reads its AST from stdin and
    # nothing about that JSON need have come from this front end -- the same
    # reason it carries its own copy of the recursion-depth guards.  So each
    # one is driven by editing a typed AST that the front end did accept.

    def _codegen_ast(self, ast: str):
        return subprocess.run([NATIVE_CODEGEN],
                              cwd=ROOT,
                              input=ast,
                              text=True,
                              capture_output=True)

    def _edited_ast(self, name: str, edit):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            _project(work)
            tree = json.loads(_typed_ast(work / name))
        edit(tree)
        return json.dumps(tree)

    def test_ads_still_rejected_where_no_device_interface_declares_it(self):
        # Device context is scoped to the DEVICE units themselves.  Strip the
        # device flag off the implementation and its ADS parameter is rejected.
        def clear_device(tree):
            tree["is_device"] = False
            for iface in tree.get("local_interfaces", []):
                iface["is_device"] = False

        result = self._codegen_ast(self._edited_ast("bump.pas", clear_device))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ADS pointers require a DEVICE compiland",
                      result.stderr + result.stdout)

    def test_uses_without_a_spliced_header_is_reported(self):

        def rename_unit(tree):
            tree["uses"][0]["name"] = "missingu"

        result = self._codegen_ast(self._edited_ast("host.pas", rename_unit))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("spliced INTERFACE header",
                      result.stderr + result.stdout)

    def test_renaming_uses_imports_are_reported_rather_than_misbound(self):
        # `USES bumpu (nudge)` would bind the local name `nudge` to the
        # exported `bump`.  Native codegen does not implement that pairing, so
        # it must say so instead of binding the call to whatever else matches.
        def rename_import(tree):
            tree["uses"][0]["imports"][0] = "nudge"

        result = self._codegen_ast(self._edited_ast("host.pas", rename_import))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("renaming USES imports are not supported",
                      result.stderr + result.stdout)


if __name__ == "__main__":
    unittest.main()
