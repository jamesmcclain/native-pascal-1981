PROGRAM renewbad;
TYPE R = RECORD v, w: INTEGER END;
     PR = ^R;
PROCEDURE probe;
VAR p: PR;
BEGIN
  NEW(p); p^.v := 1; p^.w := 2; DISPOSE(p); NEW(p); WRITELN('prefix');
  {$INITCK+} WRITELN(p^.w) {$INITCK-}
END;
BEGIN probe END.
