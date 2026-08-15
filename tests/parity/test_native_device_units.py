"""Native NVPTX lowering for every DEVICE compilation-unit root.

Set NATIVE_CODEGEN to a native codegen.pas executable.  The Python front end
supplies the normal typed-AST JSON protocol; this test isolates native lowering.
"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NATIVE_CODEGEN = os.environ.get("NATIVE_CODEGEN",
                                str(ROOT / "bin" / "codegen"))
GPU_TRIPLE = "nvptx64-nvidia-cuda"


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


@unittest.skipUnless(NATIVE_CODEGEN and os.access(NATIVE_CODEGEN, os.X_OK),
                     "requires NATIVE_CODEGEN")
class NativeDeviceUnitTests(unittest.TestCase):

    def _emit_ptx(self, source: Path) -> str:
        result = subprocess.run(
            [NATIVE_CODEGEN],
            cwd=ROOT,
            input=_typed_ast(source),
            text=True,
            capture_output=True,
            env={
                **os.environ, "PASCAL_DEVICE_TRIPLE": GPU_TRIPLE,
                "PASCAL_EMIT_PTX": "1"
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("llvm.nvvm.read.ptx.sreg.tid.x1", result.stdout)
        return result.stdout

    def test_module_interface_and_implementation_emit_nvptx(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = root / "m.pas"
            interface = root / "k"
            implementation = root / "k.pas"
            module.write_text("""DEVICE MODULE M;
VAR [SPACE(GLOBAL)] x: INTEGER32;
PROCEDURE go;
BEGIN x := THREADIDX_X; SYNCTHREADS; x := THREADIDX_X END;
.
""")
            interface.write_text("""DEVICE INTERFACE;
UNIT K (kernel);
TYPE BUFFER = SUPER ARRAY [0..*] OF INTEGER32;
PROCEDURE kernel(outp: ADS(GLOBAL) OF BUFFER);
END;
""")
            implementation.write_text("""(*$INCLUDE:'k'*)
DEVICE IMPLEMENTATION OF K;
PROCEDURE kernel(outp: ADS(GLOBAL) OF BUFFER);
BEGIN outp^[THREADIDX_X] := THREADIDX_X; SYNCTHREADS; outp^[THREADIDX_X + 1] := THREADIDX_X END;
.
""")

            module_ptx = self._emit_ptx(module)
            interface_ptx = self._emit_ptx(interface)
            implementation_ptx = self._emit_ptx(implementation)

        self.assertIn(".target sm_70", module_ptx)
        self.assertIn("%tid.x", module_ptx)
        self.assertTrue("bar.sync" in module_ptx
                        or "llvm.nvvm.barrier0" in module_ptx)
        self.assertIn(".target sm_70", interface_ptx)
        self.assertIn(".target sm_70", implementation_ptx)
        self.assertIn(".visible .entry kernel", implementation_ptx)
        self.assertTrue("st.global.u32" in implementation_ptx
                        or "st.global.b32" in implementation_ptx)
        self.assertIn("%tid.x", implementation_ptx)
        self.assertTrue("bar.sync" in implementation_ptx
                        or "llvm.nvvm.barrier0" in implementation_ptx)


if __name__ == "__main__":
    unittest.main()
