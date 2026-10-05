{ DIALECT: extended }
PROGRAM superreal;
TYPE Reals = SUPER ARRAY [1..*] OF REAL;
     P = ^Reals;
PROCEDURE probe;
VAR p: P;
BEGIN NEW(p, 2); p^[1] := 1.0; {$INITCK+} WRITELN(p^[1]:3:1) {$INITCK-} END;
BEGIN probe END.
