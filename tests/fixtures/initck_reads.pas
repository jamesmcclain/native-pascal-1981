{$INITCK-}
PROGRAM ReadSites;
TYPE Rec = RECORD f: INTEGER END;
VAR rs_x, rs_i: INTEGER;
    rs_a: ARRAY [1..2] OF INTEGER;
    rs_p: ^Rec;
BEGIN
  WRITELN({$INITCK+}rs_x + {$INITCK-}rs_x);
  WRITELN({$INITCK+}( {$INITCK-}rs_x ));
  {$INITCK+}rs_a[{$INITCK-}rs_i] := {$INITCK+}rs_x;
  WRITELN({$INITCK-}rs_p {$INITCK+}^ .f);
  WITH {$INITCK+}rs_p {$INITCK-}^ DO WRITELN(f);
  WRITELN({$INITCK+}UPPER({$INITCK-}rs_a));
  WRITELN({$INITCK+}ORD({$INITCK-}rs_x))
END.
