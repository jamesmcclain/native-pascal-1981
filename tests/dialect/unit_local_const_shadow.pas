(*$INCLUDE:'unit_local_const_shadow.inc'*)
{ A routine-local CONST shadows a unit-level one of the same name inside
  that routine only, in an IMPLEMENTATION exactly as in a PROGRAM. This
  used to be rejected as a duplicate because codegen's const table was flat
  and global. unit_local_const_shadow.host is the PROGRAM that calls it. }
IMPLEMENTATION OF shadowconst;

CONST Limit = 10;

PROCEDURE ShowOuter;
BEGIN
  WRITELN(Limit);
END;

PROCEDURE Show;
CONST Limit = 20;
BEGIN
  WRITELN(Limit);
  ShowOuter;
END;

BEGIN
END.
