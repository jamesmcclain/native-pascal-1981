{ DIALECT: extended }
PROGRAM indexck_super_nil_load(OUTPUT);
{ A checked subscript through a NIL descriptor fails deterministically
  before any data access; whether an index expression with side effects
  runs first is deliberately not pinned down by this test. }
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR p: P; i: INTEGER;
BEGIN
  p := NIL;
  i := 2;
  WRITELN('alive');
  WRITELN(p^[i])
END.
