PROGRAM globalptr;
TYPE PR = ^INTEGER;
VAR g: PR;
PROCEDURE probe;
BEGIN NEW(g); {$INITCK+} g^ := 1 {$INITCK-} END;
BEGIN probe END.
