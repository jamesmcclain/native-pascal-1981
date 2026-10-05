{ An unknown index type name is rejected. }
{ DIALECT: vintage extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Unknown type name }
PROGRAM t(output); VAR a: ARRAY [missing] OF INTEGER; BEGIN END.
