{ A user type shadowing BOOLEAN is resolved, not the builtin. }
{ DIALECT: vintage extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Array index type must be ordinal }
PROGRAM t(output); TYPE BOOLEAN = REAL; VAR a: ARRAY [BOOLEAN] OF INTEGER; BEGIN END.
