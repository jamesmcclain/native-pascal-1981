PROGRAM indexck_enum_bad(OUTPUT);
TYPE Color = (red, green, blue);
VAR a: ARRAY[green..blue] OF INTEGER; c: Color;
BEGIN
  c := red;
  WRITELN(a[c])
END.
