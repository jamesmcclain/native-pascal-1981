{ DIALECT: extended }
PROGRAM NewWideStride;
TYPE Page = ARRAY [0..65535] OF CHAR;
     Block = ARRAY [0..65535] OF Page;
     Cells = SUPER ARRAY [2..*] OF Block; P = ^Cells;
VAR p: P;
BEGIN NEW(p, 2); DISPOSE(p) END.
