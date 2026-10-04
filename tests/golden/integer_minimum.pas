{ Native compatibility is for fun, not pathology: no reserved -32768. }
PROGRAM IntegerMinimum;
CONST Minimum = -32768;
TYPE Bottom = -32768..-32767;
VAR x: INTEGER; w: WORD; b: Bottom;
    a: ARRAY [-32768..-32767] OF INTEGER;
PROCEDURE TakeInteger(v: INTEGER);
BEGIN WRITELN(v) END;
BEGIN
  x := -32768; WRITELN(x);
  x := Minimum; TakeInteger(x);
  w := -32768; WRITELN(w);
  b := -32768; WRITELN(b);
  a[-32768] := -32768; WRITELN(a[-32768])
END.
