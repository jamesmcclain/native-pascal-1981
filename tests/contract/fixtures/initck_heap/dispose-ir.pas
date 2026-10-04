{ DIALECT: extended }
PROGRAM disposeir;
TYPE R = RECORD v: INTEGER END;
     PR = ^R;
     Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
PROCEDURE probe;
VAR p: PR; s: P;
BEGIN NEW(p); NEW(s, 2); {$INITCK+} DISPOSE(p); DISPOSE(s) {$INITCK-} END;
BEGIN probe END.
