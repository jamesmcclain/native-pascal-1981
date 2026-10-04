{ DIALECT: extended }
PROGRAM indexck_super_nil_field(OUTPUT);
{ The NIL failure follows the selected descriptor, including one reached
  through a record field. }
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
     Holder = RECORD p: P; dummy: INTEGER END;
VAR h: Holder; i: INTEGER;
BEGIN
  h.p := NIL;
  i := 4;
  WRITELN('alive');
  WRITELN(h.p^[i])
END.
