{ DIALECT: extended }
PROGRAM descir;
TYPE Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
PROCEDURE probe;
VAR p: P;
BEGIN NEW(p, 2); {$INITCK+} WRITELN(UPPER(p^)) {$INITCK-} END;
BEGIN probe END.
