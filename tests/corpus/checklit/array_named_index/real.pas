{ A REAL index type is rejected. }
{ DIALECT: vintage extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Array index type must be ordinal }
PROGRAM t(output); TYPE R = REAL; VAR a: ARRAY [R] OF INTEGER; BEGIN END.
