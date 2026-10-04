PROGRAM ptrir;
TYPE PR = ^R;
     R = RECORD v: INTEGER; next: PR END;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); {$INITCK+} p^.v := 1 {$INITCK-} END;
BEGIN probe END.
