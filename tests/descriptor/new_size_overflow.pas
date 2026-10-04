{ DIALECT: extended }
PROGRAM NewSizeOverflow(output);
{$INDEXCK-}
TYPE Page = ARRAY [0..65535] OF CHAR;
     Block = ARRAY [0..65535] OF Page;
     Cube = ARRAY [0..65535] OF Block;
     Cells = SUPER ARRAY [-32767..*] OF Cube; P = ^Cells;
VAR p: P;
BEGIN NEW(p, 32767); WRITELN('UNEXPECTED: NEW returned') END.
