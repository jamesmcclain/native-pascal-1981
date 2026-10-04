{ A named index type with reversed bounds is rejected. }
{ DIALECT: vintage extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Array index type has reversed ordinal bounds }
PROGRAM t(output); TYPE Bad = 4..2; VAR a: ARRAY [Bad] OF INTEGER; BEGIN END.
