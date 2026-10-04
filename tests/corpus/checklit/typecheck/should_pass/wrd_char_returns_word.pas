{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P(OUTPUT);
VAR w: WORD; c: CHAR;
BEGIN
  c := 'A'; w := WRD(c)
END.
