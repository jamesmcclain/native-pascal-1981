{ DIALECT: extended }
{ Enumeration and subrange record fields and array elements: layout, SIZEOF,
  element stride, and a by-value record copy. These used to fail with
  "codegen: TypeAlignBytes: unsupported type". }
PROGRAM Lay(output);
TYPE Hue = (red, green, blue); Mid = green..blue; Digit = 0..9; Early = 'a'..'m';
     Rec = RECORD h: Hue; c: Early; d: Digit; m: Mid END;
     PRec = ^Rec;
VAR a: ARRAY[1..3] OF Rec; p: PRec; k: INTEGER;
PROCEDURE Show(r: Rec); BEGIN WRITELN(ORD(r.h), ' ', r.c, ' ', r.d, ' ', ORD(r.m)) END;
BEGIN
  WRITELN('size ', SIZEOF(Rec));
  FOR k := 1 TO 3 DO BEGIN a[k].h := blue; a[k].c := 'b'; a[k].d := k; a[k].m := green END;
  a[2].h := red; a[3].c := 'm';
  FOR k := 1 TO 3 DO Show(a[k]);
  NEW(p); p^ := a[3]; p^.d := 9; Show(p^)
END.
