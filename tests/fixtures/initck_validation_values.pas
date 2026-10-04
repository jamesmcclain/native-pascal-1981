PROGRAM validationvalues;
TYPE Pair = RECORD zero, minimum: INTEGER END;
     IntPtr = ^INTEGER;
{$INITCK+}
FUNCTION identity(v: INTEGER): INTEGER;
BEGIN identity := v END;
PROCEDURE probe;
VAR x, y: INTEGER;
    b: BOOLEAN;
    c: CHAR;
    p: IntPtr;
    a, copy: Pair;
    values: ARRAY [1..2] OF INTEGER;
BEGIN
  { All-zero representations and the IBM sentinel are legitimate values. }
  x := 0; y := -32768; b := FALSE; c := CHR(0); p := NIL;
  WRITELN(x, ':', y, ':', ORD(b), ':', ORD(c), ':', ORD(p = NIL));
  { Disabled writes must establish state just as checked writes do. }
  {$INITCK-}
  x := 0; y := -32768; b := FALSE; c := CHR(0); p := NIL;
  {$INITCK+}
  WRITELN(x, ':', y, ':', ORD(b), ':', ORD(c), ':', ORD(p = NIL));
  { Logical aggregate leaves and checked copies cannot reserve data bits. }
  a.zero := 0; a.minimum := -32768; copy := a;
  values[1] := copy.zero; values[2] := copy.minimum;
  WRITELN(values[1], ':', values[2]);
  { Allocation state is distinct from the initialized referent's value. }
  NEW(p); p^ := 0; WRITELN(p^);
  p^ := -32768; WRITELN(p^); DISPOSE(p);
  { Value actuals, formals, and results must accept the same bit patterns. }
  WRITELN(identity(0), ':', identity(-32768))
END;
BEGIN probe END.
