{ DIALECT: extended }
PROGRAM RejectCrossLower;
TYPE Cells2 = SUPER ARRAY [2..*] OF INTEGER; PCells2 = ^Cells2;
     Cells3 = SUPER ARRAY [3..*] OF INTEGER; PCells3 = ^Cells3;
VAR p: PCells2; q: PCells3;
BEGIN q := NIL; p := q END.
