{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ CHECK-STAGES: lexer parser codegen }
{ Codegen's own guard, with the typechecker (which rejects this first)
  bypassed: NEW in DEVICE code. }
{ CHECK-FAIL: codegen: dynamic memory allocation is not supported in DEVICE code: NEW }
DEVICE MODULE NewDevice;
TYPE PINT = ^INTEGER32;
VAR p: PINT;
PROCEDURE go;
BEGIN NEW(p) END;
.
