{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ CHECK-STAGES: lexer parser codegen }
{ Codegen's own guard, with the typechecker bypassed: a [C] EXTERN spelled
  `sqrt` misses the builtin dispatch, which compares exact spellings, and
  must still not put a call to sqrt into PTX. }
{ CHECK-FAIL: codegen: transcendental math function is not supported in DEVICE code: sqrt }
DEVICE MODULE ExternSqrtDevice;
VAR x: REAL;
FUNCTION sqrt(v: REAL): REAL [C]; EXTERN;
PROCEDURE go;
BEGIN x := sqrt(x) END;
.
