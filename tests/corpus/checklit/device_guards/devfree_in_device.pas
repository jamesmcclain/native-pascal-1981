{ DIALECT: extended }
{ CHECK-STAGES: lexer parser codegen }
{ Codegen's own guard, with the typechecker (which rejects this first)
  bypassed: device orchestration builtins are host-only. }
{ CHECK-FAIL: codegen: host-only and cannot appear in DEVICE code: DEVFREE }
DEVICE MODULE FreeDevice;
PROCEDURE go;
BEGIN DEVFREE(0) END;
.
