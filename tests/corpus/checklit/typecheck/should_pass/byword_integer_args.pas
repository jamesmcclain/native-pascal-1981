{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P(OUTPUT);
VAR w: WORD; hi, lo: INTEGER;
BEGIN
  hi := 16; lo := 32; w := BYWORD(hi, lo)
END.
