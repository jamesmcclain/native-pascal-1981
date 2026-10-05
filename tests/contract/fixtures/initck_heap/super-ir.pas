{ DIALECT: extended }
PROGRAM superir;
TYPE R = RECORD a, b: INTEGER END;
     Rs = SUPER ARRAY [1..*] OF R;
     P = ^Rs;
PROCEDURE probe(i: INTEGER);
VAR p: P;
BEGIN NEW(p, i + 3); p^[1].a := 1; {$INITCK+} WRITELN(p^[i].b) {$INITCK-} END;
BEGIN probe(1) END.
