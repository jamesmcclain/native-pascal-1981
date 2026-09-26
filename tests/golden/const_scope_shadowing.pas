PROGRAM const_scope_shadowing(OUTPUT);
{ A routine-local CONST is scoped like any other declaration: it hides an
  outer VAR, CONST or zero-argument FUNCTION of the same name inside its
  routine only, sibling routines may each declare their own, and a local
  VAR hides an outer CONST. Regression guard: codegen kept one flat CONST
  table and resolved variables first, so an outer VAR won over an inner
  CONST (even as a FOR bound or CASE label, or with a different type), an
  inner CONST leaked out of its routine, and a reused name was rejected as
  a duplicate. }
CONST
  gc = 3;
VAR
  gv: INTEGER;
  flag: BOOLEAN;
  i: INTEGER;

FUNCTION gf: INTEGER;
BEGIN
  gf := 3
END;

PROCEDURE LocalConstOverVar;
CONST gv = 7;
BEGIN
  WRITELN(gv)
END;

PROCEDURE LocalConstOverConst;
CONST gc = 7;
BEGIN
  WRITELN(gc)
END;

PROCEDURE SiblingA;
CONST k = 1;
BEGIN
  WRITELN(k)
END;

PROCEDURE SiblingB;
CONST k = 2;
BEGIN
  WRITELN(k)
END;

PROCEDURE LocalVarOverConst;
VAR gc: INTEGER;
BEGIN
  gc := 8;
  WRITELN(gc)
END;

PROCEDURE LocalConstOverFunc;
CONST gf = 9;
BEGIN
  WRITELN(gf)
END;

PROCEDURE LoopAndCase;
CONST gv = 2;
BEGIN
  FOR i := 1 TO gv DO WRITE(i);
  WRITELN;
  CASE 2 OF
    gv: WRITELN('two');
    1: WRITELN('one')
  END
END;

PROCEDURE OtherType;
CONST flag = 7;
BEGIN
  WRITELN(flag + 1)
END;

BEGIN
  gv := 5;
  flag := TRUE;
  LocalConstOverVar; WRITELN(gv);
  LocalConstOverConst; WRITELN(gc);
  SiblingA; SiblingB;
  LocalVarOverConst; WRITELN(gc);
  LocalConstOverFunc; WRITELN(gf);
  LoopAndCase;
  OtherType; WRITELN(flag)
END.
