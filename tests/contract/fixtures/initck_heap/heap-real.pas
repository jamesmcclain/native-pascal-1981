PROGRAM heapreal;
TYPE R = RECORD v: INTEGER; x: REAL END;
     PR = ^R;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); p^.v := 1; {$INITCK+} WRITELN(p^.v) {$INITCK-} END;
BEGIN probe END.
