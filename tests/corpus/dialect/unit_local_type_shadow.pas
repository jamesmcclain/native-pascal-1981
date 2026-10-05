(*$INCLUDE:'unit_local_type_shadow.inc'*)
{ A routine-local TYPE shadows a unit-level one of the same name inside that
  routine only, in an IMPLEMENTATION exactly as in a PROGRAM: `b' gets the
  local nine-element layout, so b[9] is in bounds, and the unit-level Buf
  keeps its four elements. This used to be rejected as a duplicate because
  codegen scoped no TYPE names. unit_local_type_shadow.host is the PROGRAM
  that calls it. }
IMPLEMENTATION OF shadowtype;

TYPE Buf = ARRAY [1..4] OF INTEGER;

PROCEDURE ShowOuter;
VAR a: Buf;
BEGIN
  WRITELN(UPPER(a));
END;

PROCEDURE Show;
TYPE Buf = ARRAY [1..9] OF INTEGER;
VAR b: Buf;
BEGIN
  b[9] := 7;
  WRITELN(b[9], ' ', UPPER(b));
  ShowOuter;
END;

BEGIN
END.
