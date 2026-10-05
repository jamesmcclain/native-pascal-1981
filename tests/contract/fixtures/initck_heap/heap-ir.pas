PROGRAM heapir;
TYPE R = RECORD v, w: INTEGER END;
     PR = ^R;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); p^.v := 1; {$INITCK+} WRITELN(p^.w) {$INITCK-} END;
BEGIN probe END.
