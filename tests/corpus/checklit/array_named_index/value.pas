{ A constant is not an index type. }
{ DIALECT: vintage extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Array index requires a type name, not a value: V }
PROGRAM t(output); CONST V = 1; VAR a: ARRAY [V] OF INTEGER; BEGIN END.
