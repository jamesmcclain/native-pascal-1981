"""Native kernel-entry parameter attributes and the host launch ABI.

Set NATIVE_CODEGEN to a native codegen.pas executable.  The Python front end
supplies the normal typed-AST JSON protocol; these tests isolate native
lowering, then link the launch case against the real CPU device shim and run
it -- IR shape alone has repeatedly proven insufficient here.
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

_DEVICE_INTERFACE = """DEVICE INTERFACE;
UNIT KH (scale, via_helper, via_writer);
TYPE BUF = ADS(GLOBAL) OF ARRAY [0..255] OF INTEGER32;
PROCEDURE scale(inp: BUF; outp: BUF; n: INTEGER32);
PROCEDURE via_helper(inp: BUF; outp: BUF; n: INTEGER32);
PROCEDURE via_writer(inp: BUF; n: INTEGER32);
PROCEDURE helper(b: BUF; n: INTEGER32);
PROCEDURE writer(b: BUF);
END;
"""

_DEVICE_IMPLEMENTATION = """(*$INCLUDE:'kh'*)
DEVICE IMPLEMENTATION OF KH;

PROCEDURE helper(b: BUF; n: INTEGER32);
BEGIN
END;

PROCEDURE writer(b: BUF);
BEGIN
  b^[0] := 1
END;

PROCEDURE scale(inp: BUF; outp: BUF; n: INTEGER32);
VAR i: INTEGER32;
BEGIN
  i := THREADIDX_X + BLOCKIDX_X * BLOCKDIM_X;
  IF i < n THEN
    outp^[i] := inp^[i]
END;

PROCEDURE via_helper(inp: BUF; outp: BUF; n: INTEGER32);
VAR i: INTEGER32;
BEGIN
  i := THREADIDX_X;
  helper(inp, n)
END;

PROCEDURE via_writer(inp: BUF; n: INTEGER32);
BEGIN
  writer(inp)
END;
.
"""

# Two launches of one kernel: a 1-D (grid, block) geometry and the widened
# six-value form.  The kernel adds a step to a heap cell once per thread, so
# the printed totals count how many times the shim actually ran it.
_LAUNCH_PROGRAM = """PROGRAM main(output);
TYPE
  PINT = ^INTEGER32;
VAR
  p: PINT;

PROCEDURE bump(q: PINT; step: INTEGER32);
BEGIN
  q^ := q^ + step
END;

BEGIN
  NEW(p);
  p^ := 0;
  LAUNCH(bump, 2, 3, p, 1);
  WRITELN(p^);
  LAUNCH(bump, 1, 1, 1, 2, 1, 3, p, 10);
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


@unittest.skipUnless(NATIVE_CODEGEN and os.access(NATIVE_CODEGEN, os.X_OK),
                     "requires NATIVE_CODEGEN")
class NativeKernelParamAttrTests(unittest.TestCase):
    """Facts LLVM cannot infer for a bare device pointer parameter."""

    def _emit(self, extra_env=None, emit_ptx=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "kh").write_text(_DEVICE_INTERFACE)
            implementation = root / "kh.pas"
            implementation.write_text(_DEVICE_IMPLEMENTATION)
            ast = _typed_ast(implementation)
        env = {**os.environ, "PASCAL_DEVICE_TRIPLE": GPU_TRIPLE}
        if emit_ptx:
            env["PASCAL_EMIT_PTX"] = "1"
        env.update(extra_env or {})
        result = subprocess.run([NATIVE_CODEGEN, "--dialect", "extended"],
                                cwd=ROOT,
                                input=ast,
                                text=True,
                                capture_output=True,
                                env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    @staticmethod
    def _signature(ir: str, kernel: str) -> str:
        marker = f"define ptx_kernel void @{kernel}("
        return ir[ir.index(marker):].split("\n", 1)[0]

    def test_written_through_buffer_is_not_readonly(self):
        ir = self._emit()
        signature = self._signature(ir, "scale")
        inp, outp = signature.split("%0")[0], signature.split("%0")[1]
        self.assertTrue(("nocapture readonly" in inp)
                        or ("readonly" in inp and "captures(none)" in inp))
        self.assertNotIn("readonly", outp)

    def test_buffer_forwarded_to_a_readonly_helper_stays_readonly(self):
        signature = self._signature(self._emit(), "via_helper")
        self.assertEqual(signature.count("readonly"), 2)

    def test_buffer_forwarded_to_a_writing_helper_is_not_readonly(self):
        self.assertNotIn("readonly", self._signature(self._emit(),
                                                     "via_writer"))

    def test_pointer_params_carry_pointee_alignment_and_extent(self):
        signature = self._signature(self._emit(), "scale")
        self.assertIn("align 4 dereferenceable(1024)",
                      signature)  # 256 * 4 bytes

    def test_natural_alignment_reaches_the_emitted_ptx(self):
        ptx = self._emit(emit_ptx=True)
        self.assertIn(".visible .entry scale", ptx)
        self.assertIn(".ptr .global .align 4", ptx)

    def test_noalias_is_absent_unless_opted_into(self):
        self.assertNotIn("noalias", self._emit())

    def test_noalias_present_on_every_buffer_when_opted_into(self):
        ir = self._emit(extra_env={"PASCAL_NOALIAS_KERNEL_PARAMS": "1"})
        self.assertEqual(self._signature(ir, "scale").count("noalias"), 2)

    def test_host_triple_gets_no_kernel_entry_attributes(self):
        # The x86 CPU-device path has no kernel entries at all, so none of
        # these facts may appear.  This uses a body free of index intrinsics:
        # lowering those against a host triple is a separate, unimplemented
        # concern, and it is the attributes under test here.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "kc").write_text(
                "DEVICE INTERFACE;\n"
                "UNIT KC (copy0);\n"
                "TYPE BUF = ADS(GLOBAL) OF ARRAY [0..255] OF INTEGER32;\n"
                "PROCEDURE copy0(inp: BUF; outp: BUF);\n"
                "END;\n")
            implementation = root / "kc.pas"
            implementation.write_text("(*$INCLUDE:'kc'*)\n"
                                      "DEVICE IMPLEMENTATION OF KC;\n"
                                      "PROCEDURE copy0(inp: BUF; outp: BUF);\n"
                                      "BEGIN\n"
                                      "  outp^[0] := inp^[0]\n"
                                      "END;\n"
                                      ".\n")
            ast = _typed_ast(implementation)
        result = subprocess.run([NATIVE_CODEGEN, "--dialect", "extended"],
                                cwd=ROOT,
                                input=ast,
                                text=True,
                                capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for attribute in ("dereferenceable", "readonly", "noalias",
                          "ptx_kernel"):
            self.assertNotIn(attribute, result.stdout)


@unittest.skipUnless(NATIVE_CODEGEN and os.access(NATIVE_CODEGEN, os.X_OK),
                     "requires NATIVE_CODEGEN")
class NativeLaunchAbiTests(unittest.TestCase):
    """LAUNCH resolves its entry the way the CUDA driver does."""

    def _emit(self, env_extra=None):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "main.pas"
            source.write_text(_LAUNCH_PROGRAM)
            ast = _typed_ast(source)
        result = subprocess.run([NATIVE_CODEGEN, "--dialect", "extended"],
                                cwd=ROOT,
                                input=ast,
                                text=True,
                                capture_output=True,
                                env={
                                    **os.environ,
                                    **(env_extra or {})
                                })
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_launch_goes_through_module_load_lookup_and_launch(self):
        ir = self._emit()
        self.assertIn(
            "call ptr @pas_dev_module_load(ptr @__pas_klaunch_registry", ir)
        self.assertIn("@pas_dev_module_get_function", ir)
        self.assertIn("@pas_dev_launch", ir)
        self.assertIn("launch_argv", ir)

    def test_one_thunk_and_one_registry_entry_per_kernel(self):
        ir = self._emit()
        # Two launches of the same kernel must share one thunk: a second
        # emission would uniquify into an unregistered `.1` symbol.
        self.assertEqual(ir.count("define internal void @__pas_klaunch_bump("),
                         1)
        self.assertNotIn("__pas_klaunch_bump.1", ir)
        self.assertIn("@__pas_kregnames = constant [1 x ptr]", ir)
        self.assertIn("i64 1 }", ir)

    def test_cuda_backend_emits_no_registry_or_thunk(self):
        ir = self._emit(env_extra={"PASCAL_DEVICE_BACKEND": "cuda"})
        # The kernel is the loaded PTX module, dispatched by name, so the host
        # object carries neither an in-process registry nor a dispatch thunk,
        # and the PTX blob is supplied by its own object at link time.
        self.assertNotIn("__pas_klaunch_bump", ir)
        self.assertNotIn("__pas_kregnames", ir)
        self.assertIn("@__pas_device_ptx = external constant", ir)
        self.assertIn("call ptr @pas_dev_module_load(ptr null", ir)

    def test_both_geometry_forms_drive_the_kernel_the_right_number_of_times(
            self):
        runtime_lib = ROOT / "runtime" / "build" / "libpascalrt.a"
        if not runtime_lib.exists():
            subprocess.run(["make", "-C", str(ROOT / "runtime")],
                           check=True,
                           capture_output=True)
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            ll = work / "main.ll"
            ll.write_text(self._emit())
            exe = work / "main"
            link = subprocess.run(
                ["clang",
                 str(ll),
                 str(runtime_lib), "-lm", "-o",
                 str(exe)],
                capture_output=True,
                text=True)
            self.assertEqual(link.returncode, 0, link.stderr)
            run = subprocess.run([str(exe)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        # grid 2 x block 3 = 6 threads, each adding 1; then a 1x1x1 grid of
        # 2x1x3 blocks = 6 more threads, each adding 10.
        self.assertEqual(run.stdout.split(), ["6", "66"])


if __name__ == "__main__":
    unittest.main()
