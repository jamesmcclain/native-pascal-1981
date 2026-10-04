{ DIALECT: extended }
PROGRAM RejectNewRecordLayout;
TYPE A = ARRAY [0..65535] OF CHAR;
     B = ARRAY [0..65535] OF A;
     Huge = RECORD data: B END;
     Cells = SUPER ARRAY [2..*] OF Huge; P = ^Cells;
VAR p: P;
BEGIN NEW(p, 2) END.
