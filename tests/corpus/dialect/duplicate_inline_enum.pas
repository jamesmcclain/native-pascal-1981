{ DIALECT: vintage extended }
{ NEW-12r: two inline enumerations that reuse a member name in one scope are
  rejected by the typechecker with a located diagnostic (as well as an inline
  enumeration colliding with a named enumeration, CONST or VAR). Shadowing an
  enclosing scope's inline enumeration member in a nested routine stays legal. }
PROGRAM DuplicateInlineEnum(OUTPUT);
CONST
  dupconst = 1;
TYPE
  Rec = RECORD
    x: (alpha, beta);
    y: (BETA, gamma)
  END;
  VarRec = RECORD
    CASE INTEGER OF
      1: (u: (one, two));
      2: (v: (TWO, three))
  END;
VAR
  a: (red, green);
  b: (Green, blue);
  arr: ARRAY [1..2] OF (red, yellow);
  c: (dupconst, fresh);
  dupvar: INTEGER;
  d: (DUPVAR, other);

PROCEDURE Inner;
VAR
  p: (red, violet);
  q: (Violet, indigo);
BEGIN
END;

BEGIN
END.
