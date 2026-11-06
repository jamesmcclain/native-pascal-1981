{ DIALECT: vintage extended }
{ CMP-23: an index past the selected SUPER ARRAY's upper bound in
  l^[i]^.v fails before the element pointer is loaded. }
PROGRAM SuperPointerSelectIndex(OUTPUT);
{$INDEXCK+}
TYPE
  R = RECORD v: INTEGER END;
  PR = ^R;
  SA = SUPER ARRAY [0..*] OF PR;
VAR
  l: ^SA;
  i: INTEGER;
BEGIN
  NEW(l, 1);
  FOR i := 0 TO 1 DO
  BEGIN
    NEW(l^[i]);
    l^[i]^.v := i + 1
  END;
  WRITELN('last ', l^[1]^.v:1);
  i := 2;
  WRITELN(l^[i]^.v:1);
  WRITELN('not reached')
END.
