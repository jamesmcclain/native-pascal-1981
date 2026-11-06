{ DIALECT: extended }
{ OPT: 0 1 2 3 }
PROGRAM encode_enum_extended;
{ Extended WRITE prints an enumerated value by name, so ENCODE does; the
  wide integers and REAL32 format as WRITE formats them. }
TYPE color = (red, green, blue);
     warm = red..green;
VAR s: LSTRING(8); e: color; w: warm; b: BOOLEAN;
    i32: INTEGER32; i64: INTEGER64; w32: WORD32; w8: WORD8; r32: REAL32;
    u: LSTRING(30);
BEGIN
  e := green;
  IF ENCODE(s, e) THEN WRITELN('[', s, ']');
  IF ENCODE(s, e:7) THEN WRITELN('[', s, ']');
  IF ENCODE(s, blue) THEN WRITELN('[', s, ']');
  w := red;
  IF ENCODE(s, w) THEN WRITELN('[', s, ']');
  b := e = green;
  IF ENCODE(s, b) THEN WRITELN('[', s, ']');
  i32 := -100000;
  IF ENCODE(u, i32) THEN WRITELN('[', u, ']');
  i64 := 1234567890123;
  IF ENCODE(u, i64:16) THEN WRITELN('[', u, ']');
  w32 := 4000000000;
  IF ENCODE(u, w32) THEN WRITELN('[', u, ']');
  w8 := 255;
  IF ENCODE(u, w8:4) THEN WRITELN('[', u, ']');
  r32 := 1.5;
  IF ENCODE(u, r32:6:2) THEN WRITELN('[', u, ']');
  IF NOT ENCODE(s, i64) THEN WRITELN('no [', s, ']');
END.
