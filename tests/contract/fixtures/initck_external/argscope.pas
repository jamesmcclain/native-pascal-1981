PROGRAM argscope;
FUNCTION cfive(n: INTEGER): INTEGER [C]; EXTERN;
FUNCTION pfive(r: REAL): INTEGER; BEGIN pfive := 5 END;
PROCEDURE probe;
VAR u, y, z: INTEGER;
BEGIN
  {$INITCK-} y := cfive(u); z := pfive(u); {$INITCK+}
  WRITELN(y); WRITELN(z)
  {$INITCK-}
END;
BEGIN probe END.
