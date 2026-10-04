{ DIALECT: extended }
PROGRAM RejectNewOveraligned;
TYPE Wide = VECTOR [8] OF REAL;
     Cells = SUPER ARRAY [2..*] OF Wide; P = ^Cells;
VAR p: P;
BEGIN NEW(p, 2) END.
