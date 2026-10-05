{ DIALECT: extended }
PROGRAM RejectNewElementLayout;
TYPE A = ARRAY [0..65535] OF CHAR;
     B = ARRAY [0..65535] OF A;
     C = ARRAY [0..65535] OF B;
     D = ARRAY [0..65535] OF C;
     Cells = SUPER ARRAY [2..*] OF D; P = ^Cells;
VAR p: P;
BEGIN NEW(p, 2) END.
