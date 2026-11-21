{ DIALECT: vintage extended }
{ NEW-31: REAL or string CONSTs (and non-CONST identifiers) used as array or
  subrange bounds must be rejected by the typechecker with a source location,
  not passed through to codegen. }
PROGRAM SubrangeNonOrdinalBound;
CONST
  R = 1.5;
  S = 'ab';
TYPE
  A1 = ARRAY [1..R] OF INTEGER;
  A2 = ARRAY [R..10] OF INTEGER;
  A3 = ARRAY [1..S] OF INTEGER;
  A4 = ARRAY [S..10] OF INTEGER;
  Sub1 = 1..R;
  Sub2 = S..10;
  Sup1 = SUPER ARRAY [R..*] OF INTEGER;
  A5 = ARRAY [-R..10] OF INTEGER;
VAR
  v: INTEGER;
  a6: ARRAY [1..v] OF INTEGER;
BEGIN
END.
