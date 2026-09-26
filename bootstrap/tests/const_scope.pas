{ A routine-local CONST is scoped: it hides an outer VAR, CONST or
  FUNCTION inside its routine only, siblings may reuse a name, a local VAR
  hides an outer CONST, and CONST names are case-insensitive. The native
  compiler's tests/golden/const_scope_shadowing.pas checks the same rules. }
(*$INCLUDE:'testio.inc'*)
PROGRAM const_scope(input, output);
USES testio;

CONST
  gc = 3;
  Big = 7;

VAR
  gv: INTEGER;
  i: INTEGER;

FUNCTION gf: INTEGER;
BEGIN
  gf := 3;
END;

PROCEDURE LocalConstOverVar;
CONST
  gv = 7;
BEGIN
  WriteInt(gv); WRITELN;
END;

PROCEDURE LocalConstOverConst;
CONST
  gc = 7;
BEGIN
  WriteInt(gc); WRITELN;
END;

PROCEDURE SiblingA;
CONST
  k = 1;
BEGIN
  WriteInt(k); WRITELN;
END;

PROCEDURE SiblingB;
CONST
  k = 2;
BEGIN
  WriteInt(k); WRITELN;
END;

PROCEDURE LocalVarOverConst;
VAR
  gc: INTEGER;
BEGIN
  gc := 8;
  WriteInt(gc); WRITELN;
END;

PROCEDURE LocalConstOverFunc;
CONST
  gf = 9;
BEGIN
  WriteInt(gf); WRITELN;
END;

PROCEDURE ForBound;
CONST
  gv = 2;
BEGIN
  FOR i := 1 TO gv DO WriteInt(i);
  WRITELN;
END;

BEGIN
  gv := 5;
  LocalConstOverVar; WriteInt(gv); WRITELN;
  LocalConstOverConst; WriteInt(gc); WRITELN;
  SiblingA; SiblingB;
  LocalVarOverConst; WriteInt(gc); WRITELN;
  LocalConstOverFunc; WriteInt(gf); WRITELN;
  ForBound;
  WriteInt(BIG); WriteInt(big); WRITELN;
END.
