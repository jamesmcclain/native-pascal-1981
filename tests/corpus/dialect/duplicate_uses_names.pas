{ DIALECT: vintage extended }
{ NEW-7r: names imported from a USES interface share the importing unit's
  top-level declaration scope, so redeclaring an imported constant, type,
  variable, routine, enumeration member or USES alias, or importing the same
  name from two USES interfaces, is a duplicate-declaration error. }
INTERFACE;
UNIT u1 (C1, T1, V1, P1, F1, E1);
CONST
  C1 = 1;
TYPE
  T1 = INTEGER;
  E1 = (red, green);
VAR
  V1: INTEGER;
PROCEDURE P1;
FUNCTION F1: INTEGER;
END;

INTERFACE;
UNIT u2 (C1, P2);
CONST
  C1 = 2;
PROCEDURE P2;
END;

PROGRAM DuplicateUsesNames(OUTPUT);
USES u1, u2 (C1, AliasedP2);
CONST
  t1 = 9;
VAR
  v1: INTEGER;
  RED: INTEGER;
  aliasedp2: INTEGER;

PROCEDURE p1;
BEGIN
END;

FUNCTION f1: INTEGER;
BEGIN
  f1 := 0
END;

PROCEDURE ShadowOk;
VAR
  C1: INTEGER;
  P1: INTEGER;
BEGIN
  C1 := 1;
  P1 := C1
END;

BEGIN
END.
