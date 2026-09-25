{ DIALECT: extended }
PROGRAM indexck_wide_ordinals(OUTPUT);
CONST c200 = CHR(200); c201 = CHR(201);
TYPE Color = (red, green, blue);
VAR a: ARRAY[-2..2] OF INTEGER;
    w: ARRAY[32768..32769] OF INTEGER;
    c: ARRAY[c200..c201] OF INTEGER;
    b: ARRAY[FALSE..TRUE] OF INTEGER;
    e: ARRAY[red..blue] OF INTEGER;
    n: ARRAY[-128..127] OF INTEGER;
    u: ARRAY[0..255] OF INTEGER;
    si: INTEGER8; ui: WORD8; li: INTEGER64; wi: WORD;
    ch: CHAR; flag: BOOLEAN; color: Color;
BEGIN
  li := -2; a[li] := 11; li := 2; a[li] := 12;
  si := -128; n[si] := 13; si := 127; n[si] := 14;
  ui := 255; u[ui] := 15;
  wi := 32768; w[wi] := 16; wi := 32769; w[wi] := 17;
  ch := CHR(200); c[ch] := 18; ch := CHR(201); c[ch] := 19;
  flag := FALSE; b[flag] := 20; flag := TRUE; b[flag] := 21;
  color := red; e[color] := 22; color := blue; e[color] := 23;
  WRITELN(a[-2], ' ', a[2], ' ', n[-128], ' ', n[127], ' ', u[255]);
  WRITELN(w[32768], ' ', w[32769], ' ', c[CHR(200)], ' ', c[CHR(201)]);
  WRITELN(b[FALSE], ' ', b[TRUE], ' ', e[red], ' ', e[blue])
END.
