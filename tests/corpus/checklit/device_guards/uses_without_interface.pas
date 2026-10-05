{ DIALECT: extended }
{ CHECK-STAGES: lexer parser codegen }
{ Codegen's own guard, with the typechecker (which rejects this first)
  bypassed: a USES unit must have its INTERFACE spliced in. }
{ CHECK-FAIL: codegen: USES unit needs a spliced INTERFACE header: missingu }
PROGRAM host(output);
USES missingu (bump);
BEGIN
END.
