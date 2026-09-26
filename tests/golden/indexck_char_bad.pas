{ DIALECT: extended }
PROGRAM indexck_char_bad(OUTPUT);
CONST c200 = CHR(200); c201 = CHR(201);
VAR a: ARRAY[c200..c201] OF INTEGER; ch: CHAR;
BEGIN
  ch := CHR(199);
  WRITELN(a[ch])
END.
