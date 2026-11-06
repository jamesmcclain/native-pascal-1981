{ DIALECT: vintage extended }
{ NEW-7: an identifier is declared at most once in a block. Constants,
  types, variables, parameters, enumeration members, routines and
  identifier labels share one case-insensitive name space per block, so
  each second declaration below is a located error. CONST W and VAR w
  were both accepted, and the later one silently won. }
PROGRAM DuplicateDeclarations(OUTPUT);
LABEL
  done, Done, lab;
CONST
  W = 1;
  k = 2;
  K = 3;
TYPE
  t = INTEGER;
  T = CHAR;
  colour = (red, green);
  shade = (blue, RED);
  hue = (cyan, hue);
VAR
  w: INTEGER;
  a, A: INTEGER;
  t2, Colour: INTEGER;
  green: CHAR;
  LAB: INTEGER;
  p: INTEGER;
  q: INTEGER;

PROCEDURE p;
BEGIN
END;

PROCEDURE r;
BEGIN
END;

PROCEDURE r;
BEGIN
END;

FUNCTION f(x: INTEGER; X: CHAR): INTEGER;
VAR
  x2, f2: INTEGER;
  x: INTEGER;
CONST
  X2 = 4;
BEGIN
  f := 0
END;

PROCEDURE Q;
BEGIN
END;

BEGIN
END.
