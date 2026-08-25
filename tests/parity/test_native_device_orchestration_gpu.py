"""Device orchestration on a REAL GPU, lowered by native codegen.pas.

The GPU counterpart of test_native_device_orchestration.py: the *same*
Pascal vector-add (a DEVICE INTERFACE/IMPLEMENTATION kernel + a host PROGRAM
that DEVALLOCs, H2D-copies, LAUNCHes, D2H-copies, and prints) but run
through runtime/cuda_launch.c (cuMemAlloc/cuMemcpyHtoD/cuModuleLoadData/
cuLaunchKernel/...) instead of the CPU shim. Mirrors the Python reference's
tests/integration/test_device_orchestration_gpu.py.

Gated by @requires_gpu (tests/support.py) so it skips cleanly on machines
without an NVIDIA GPU, the NVPTX backend, libcuda, or the CUDA toolkit
headers -- this development VM has none of those, so this test has never
been run; it is expected to be exercised on a machine that does have a GPU.

The device kernel is compiled to PTX (native codegen.pas with
PASCAL_EMIT_PTX=1 PASCAL_DEVICE_TRIPLE=nvptx64-nvidia-cuda) and packaged as
a NUL-terminated __pas_device_ptx data object that the host (compiled with
PASCAL_DEVICE_BACKEND=cuda) references as an external symbol; the host
links that blob + the CUDA shim archive + -lcuda. The host emits no
in-process launch thunk and no kernel-symbol reference, so no device-unit
.ll is linked -- same packaging the reference test documents.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tests.support import RUNTIME_DIR, requires_gpu

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


def _project(directory: Path) -> None:
    (directory / "vadd.inc").write_text(_INTERFACE)
    (directory / "vadd.pas").write_text(_IMPLEMENTATION)
    (directory / "host.pas").write_text(_HOST)


def _build_cuda_runtime(tmpdir: str) -> str:
    """Build the CUDA-shim runtime archive into an ISOLATED temp dir.

    Building in a *copy* of the runtime sources keeps the shared source-tree
    runtime/build/ (which every CPU-path link test links against as
    libpascalrt.a) completely untouched. Raises unittest.SkipTest if the
    build fails, so a GPU box with a broken/incomplete CUDA toolkit skips
    cleanly instead of erroring.

    Native's runtime/Makefile spells this `make cuda` -> build/libpascalrt_cuda.a
    (not the reference's `make DEVICE_SHIM=cuda` -> build/libpascalrt.a).
    """
    for name in os.listdir(RUNTIME_DIR):
        if name == "build":
            continue
        src = os.path.join(RUNTIME_DIR, name)
        if os.path.isfile(src):
            shutil.copy(src, os.path.join(tmpdir, name))
    r = subprocess.run(["make", "-C", tmpdir, "cuda"],
                       capture_output=True,
                       text=True)
    if r.returncode != 0:
        raise unittest.SkipTest(f"CUDA runtime build failed: {r.stderr}")
    out = os.path.join(tmpdir, "build", "libpascalrt_cuda.a")
    if not os.path.exists(out):
        raise unittest.SkipTest(
            "CUDA runtime build failed: no archive produced")
    return out


# RETIREMENT MARKER: Remove this Python predecessor after it and
# tests/gpu_orchestration.sh both pass on the same real NVIDIA GPU. Keep it
# until that side-by-side run confirms compilation, linking, execution, and
# exact vector output in both implementations.
@requires_gpu
@unittest.skipUnless(NATIVE_CODEGEN and os.access(NATIVE_CODEGEN, os.X_OK),
                     "requires NATIVE_CODEGEN")
class DeviceOrchestrationGPUTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls._runtime_tmp = tempfile.mkdtemp(prefix="pascalrt-cuda-")
        try:
            cls.runtime_lib = _build_cuda_runtime(cls._runtime_tmp)
        except BaseException:
            shutil.rmtree(cls._runtime_tmp, ignore_errors=True)
            cls._runtime_tmp = None
            raise

    @classmethod
    def tearDownClass(cls):
        tmp = getattr(cls, "_runtime_tmp", None)
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_vector_add_runs_on_gpu(self):
        cuda_home = os.environ.get("CUDA_HOME", "/usr/local/cuda")
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            _project(work)

            # 1. device unit -> PTX (native codegen's NVPTX target-machine
            # backend, PASCAL_EMIT_PTX=1).
            env = dict(os.environ)
            env["PASCAL_EMIT_PTX"] = "1"
            env["PASCAL_DEVICE_TRIPLE"] = "nvptx64-nvidia-cuda"
            ptx = subprocess.run(
                [NATIVE_CODEGEN],
                cwd=ROOT,
                input=_typed_ast(work / "vadd.pas"),
                text=True,
                capture_output=True,
                env=env,
            )
            self.assertEqual(ptx.returncode, 0, ptx.stderr + ptx.stdout)
            ptx_path = work / "vadd.ptx"
            ptx_path.write_text(ptx.stdout)

            # 2. host program -> .ll with the cuda device backend. This emits
            # no in-process launch thunk and no kernel-symbol reference, so
            # the host .ll needs no device-unit .ll to link against -- the
            # real kernel comes from the PTX loaded at run time.
            env = dict(os.environ)
            env["PASCAL_DEVICE_BACKEND"] = "cuda"
            host_ir = subprocess.run(
                [NATIVE_CODEGEN],
                cwd=ROOT,
                input=_typed_ast(work / "host.pas"),
                text=True,
                capture_output=True,
                env=env,
            )
            self.assertEqual(host_ir.returncode, 0,
                             host_ir.stderr + host_ir.stdout)
            host_ll = work / "host.ll"
            host_ll.write_text(host_ir.stdout)

            # 3. objectify the PTX text into a __pas_device_ptx data blob
            # (PTX *text* + trailing NUL; NOT ptxas/cubin output).
            blob_s = work / "dev_ptx_blob.s"
            blob_s.write_text('\t.section .rodata\n'
                              '\t.globl __pas_device_ptx\n'
                              '__pas_device_ptx:\n'
                              f'\t.incbin "{ptx_path}"\n'
                              '\t.byte 0\n')
            blob_o = work / "dev_ptx_blob.o"
            asm = subprocess.run(
                ["clang", "-c", str(blob_s), "-o",
                 str(blob_o)],
                capture_output=True,
                text=True)
            self.assertEqual(asm.returncode, 0, asm.stderr)

            # 4. link host .ll + PTX blob + CUDA shim + -lcuda.
            exe = work / "vadd-gpu"
            link = subprocess.run(
                [
                    "clang",
                    str(host_ll),
                    str(blob_o),
                    self.runtime_lib,
                    "-L" + os.path.join(cuda_home, "lib64", "stubs"),
                    "-lcuda",
                    "-o",
                    str(exe),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(link.returncode, 0, link.stderr)

            # 5. run on the GPU.
            run = subprocess.run([str(exe)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        # c[i] = a[i] + b[i] = i + 2i = 3i, for i = 0..7.
        self.assertEqual(run.stdout.split(),
                         ["0", "3", "6", "9", "12", "15", "18", "21"])


if __name__ == "__main__":
    unittest.main()
