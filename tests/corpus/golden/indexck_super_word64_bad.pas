{ DIALECT: extended }
PROGRAM indexck_super_word64_bad(OUTPUT);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR p: P; w: WORD64;
BEGIN
  NEW(p, 9);
  w := MAXWORD64;
  p^[w] := 7;
  WRITELN('unreachable')
END.
