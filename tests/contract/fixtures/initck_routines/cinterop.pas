PROGRAM cinterop;
FUNCTION cvalue: INTEGER; EXTERN;
PROCEDURE csink(n: INTEGER); EXTERN;
PROCEDURE csinkc(n: INTEGER) [C]; EXTERN;
PROCEDURE drive; EXTERN;
PROCEDURE probe_cb(n: INTEGER); BEGIN {$INITCK+} WRITELN(n) {$INITCK-} END;
FUNCTION unsetres: INTEGER; BEGIN END;
PROCEDURE probe(bad: BOOLEAN);
VAR x, y, u: INTEGER;
BEGIN
  y := unsetres; x := cvalue;
  {$INITCK+} WRITELN(x); {$INITCK-}
  csink(u); drive;
  IF bad THEN BEGIN {$INITCK+} csinkc(u) {$INITCK-} END;
  WRITELN('after')
END;
BEGIN probe(FALSE); probe(TRUE) END.
