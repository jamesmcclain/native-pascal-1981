"""Host device orchestration on the CPU-device (host-triple) path, lowered by
native codegen.pas: DEVALLOC/DEVCOPYTO/DEVCOPYFROM/DEVFREE plus a device
kernel reading THREADIDX_X/BLOCKIDX_X/BLOCKDIM_X/GRIDDIM_X on a host triple.

Set NATIVE_CODEGEN to a native codegen.pas executable. The Python front end
supplies the normal typed-AST JSON protocol; this test isolates native
lowering, mirroring test_native_host_uses_device.py's structure.
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
UNIT vaddu (add);
TYPE
  BUFFER = SUPER ARRAY [0..*] OF INTEGER32;
PROCEDURE add(a: ADS(GLOBAL) OF BUFFER; b: ADS(GLOBAL) OF BUFFER;
              c: ADS(GLOBAL) OF BUFFER; n: INTEGER32);
END;
"""

_IMPLEMENTATION = """\
(*$INCLUDE:'vadd.inc'*)
DEVICE IMPLEMENTATION OF vaddu;
PROCEDURE add(a: ADS(GLOBAL) OF BUFFER; b: ADS(GLOBAL) OF BUFFER;
              c: ADS(GLOBAL) OF BUFFER; n: INTEGER32);
VAR
  i, stride: INTEGER32;
BEGIN
  i := THREADIDX_X + BLOCKIDX_X * BLOCKDIM_X;
  stride := BLOCKDIM_X * GRIDDIM_X;
  WHILE i < n DO
  BEGIN
    c^[i] := a^[i] + b^[i];
    i := i + stride
  END
END;
.
"""

_HOST = """\
(*$INCLUDE:'vadd.inc'*)
PROGRAM host(output);
USES vaddu (add);
CONST n = 8;
VAR
  ha, hb, hc: ARRAY [0..7] OF INTEGER32;
  da, db, dc: ADRMEM;
  i: INTEGER;
  bytes: INTEGER;
BEGIN
  bytes := n * 4;
  FOR i := 0 TO n - 1 DO
  BEGIN
    ha[i] := i;
    hb[i] := i + i;
    hc[i] := 0
  END;
  da := DEVALLOC(bytes);
  db := DEVALLOC(bytes);
  dc := DEVALLOC(bytes);
  DEVCOPYTO(da, ADR ha, bytes);
  DEVCOPYTO(db, ADR hb, bytes);
  LAUNCH(add, 1, n, da, db, dc, n);
  DEVCOPYFROM(ADR hc, dc, bytes);
  FOR i := 0 TO n - 1 DO
    WRITELN(hc[i]);
  DEVFREE(da);
  DEVFREE(db);
  DEVFREE(dc)
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
    (directory / "vadd.inc").write_text(_INTERFACE)
    (directory / "vadd.pas").write_text(_IMPLEMENTATION)
    (directory / "host.pas").write_text(host_source)


@unittest.skipUnless(NATIVE_CODEGEN and os.access(NATIVE_CODEGEN, os.X_OK),
                     "requires NATIVE_CODEGEN")
class DeviceOrchestrationTests(unittest.TestCase):

    def _codegen(self, source: Path, expect_success: bool = True):
        result = subprocess.run(
            [NATIVE_CODEGEN, "--dialect", "extended"],
            cwd=ROOT,
            input=_typed_ast(source),
            text=True,
            capture_output=True,
        )
        if expect_success:
            self.assertEqual(result.returncode, 0,
                             result.stderr + result.stdout)
        return result

    def test_allocate_copy_launch_copyback_runs(self):
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
            (work / "vadd.ll").write_text(
                self._codegen(work / "vadd.pas").stdout)
            exe = work / "vadd-orchestration"
            link = subprocess.run(
                [
                    "clang",
                    str(work / "host.ll"),
                    str(work / "vadd.ll"),
                    str(runtime_lib), "-lm", "-o",
                    str(exe)
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(link.returncode, 0, link.stderr)
            run = subprocess.run([str(exe)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        # c[i] = a[i] + b[i] = i + 2i = 3i, for i = 0..7.
        self.assertEqual(run.stdout.split(),
                         ["0", "3", "6", "9", "12", "15", "18", "21"])

    # DEVALLOC/DEVCOPYTO/DEVCOPYFROM/DEVFREE are host-only: the reference
    # type checker rejects each inside DEVICE code, with its own equivalent
    # message. Native codegen carries its own copy of the restriction because
    # it reads its AST from stdin -- nothing about that JSON need have come
    # from a front end that already enforced it (test_native_host_uses_device.py
    # makes the same argument for the ADS-context restriction).

    def _edited_ast(self, name: str, edit):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            _project(work)
            tree = json.loads(_typed_ast(work / name))
        edit(tree)
        return json.dumps(tree)

    def _device_orchestration_call_rejected(self, call_name: str, args: list):

        def splice_call(tree):
            # Splice a bare ProcCallStmt for the orchestration builtin into
            # the device kernel's own body -- codegen's is_device_compiland
            # check should reject it regardless of anything the front end
            # would itself have caught first.
            stmts = tree["decls"][0]["body"]["body"]
            stmts.insert(0, {
                "__node_type__": "ProcCallStmt",
                "name": call_name,
                "args": args,
            })

        ast = self._edited_ast("vadd.pas", splice_call)
        result = subprocess.run([NATIVE_CODEGEN, "--dialect", "extended"],
                                cwd=ROOT,
                                input=ast,
                                text=True,
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("host-only", result.stderr + result.stdout)

    def test_devfree_rejected_inside_device_code(self):
        self._device_orchestration_call_rejected("DEVFREE", [{
            "__node_type__": "IntLiteral",
            "value": 0
        }])


if __name__ == "__main__":
    unittest.main()
