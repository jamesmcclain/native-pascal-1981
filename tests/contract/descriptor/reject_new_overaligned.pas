{ DIALECT: extended }
PROGRAM RejectNewOveraligned;
TYPE Wide = VECTOR [8] OF REAL;
     Cells = SUPER ARRAY [2..*] OF Wide; TP = ^Cells;
VAR p: TP;
BEGIN NEW(p, 2) END.
