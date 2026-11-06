{$STACKCK-}
PROGRAM toggles;
{ Each routine's STACKCK setting is the one at its name token. }
{$INITCK-}{$MATHCK-}
{$STACKCK+}
PROCEDURE checked;
VAR a: ARRAY [0..9999] OF INTEGER;
BEGIN a[0] := 1; WRITELN(a[0]) END;
{$STACKCK-}
PROCEDURE unchecked;
VAR a: ARRAY [0..9999] OF INTEGER;
BEGIN a[0] := 2; WRITELN(a[0]) END;
{$STACKCK+}
PROCEDURE outer;
  {$STACKCK-}
  PROCEDURE inner;
  VAR a: ARRAY [0..9999] OF INTEGER;
  BEGIN a[0] := 3; WRITELN(a[0]) END;
BEGIN inner END;
FUNCTION
  {$STACKCK-} late: INTEGER;
BEGIN late := 4 END;
BEGIN checked; unchecked; outer; WRITELN(late) END.
