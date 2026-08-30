{ DIALECT: extended }
{ Variadic [C] call against real libc snprintf: the arguments past the
  declared (fixed) parameters get C's default argument promotions, so a
  narrow signed INTEGER8 sign-extends to int, a narrow unsigned WORD
  zero-extends to int (60000 must stay 60000, not become -5536), a REAL32
  widens to double, and an already-wide pointer/INTEGER32 passes through
  untouched. Any of those going wrong is visible in the formatted text. }
PROGRAM VarargsCCall(OUTPUT);
TYPE
  Str255 = LSTRING(255);
  CharBuf = ARRAY [0..255] OF CHAR;
  PCharBuf = ^CharBuf;

FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
FUNCTION snprintf(dst: ADRMEM; sz: INTEGER64; fmt: ADRMEM): CINT [C, VARARGS]; EXTERN;

VAR
  buf: ADRMEM;
  n: CINT;
  small: INTEGER8;
  big_word: WORD;
  frac: REAL32;
  wide: INTEGER32;

FUNCTION CStr(s: Str255): ADRMEM;
VAR
  raw: ADRMEM;
  pbuf: PCharBuf;
  i, len: INTEGER;
BEGIN
  len := ORD(s[0]);
  raw := malloc(256);
  pbuf := raw;
  FOR i := 1 TO len DO pbuf^[i - 1] := s[i];
  pbuf^[len] := CHR(0);
  CStr := raw;
END;

PROCEDURE PutCStr(p: ADRMEM);
VAR
  pbuf: PCharBuf;
  i: INTEGER;
BEGIN
  pbuf := p;
  i := 0;
  WHILE (i < 255) AND THEN (pbuf^[i] <> CHR(0)) DO
  BEGIN
    WRITE(pbuf^[i]);
    i := i + 1;
  END;
  WRITELN;
END;

BEGIN
  buf := malloc(256);

  small := -7;
  big_word := 60000;
  frac := 2.5;
  { An already-32-bit tail argument is passed through with no extension at
    all. (Kept inside 16 bits: an INTEGER literal is 16-bit in this dialect,
    so a larger constant would be truncated before it ever reached the
    call -- unrelated to the promotion under test here.) }
  wide := 12345;

  n := snprintf(buf, 256, CStr('%d|%u|%.2f|%d'), small, big_word, frac, wide);
  WRITELN(n);
  PutCStr(buf);

  { A CHAR tail argument promotes to int too -- printed back as %c. }
  n := snprintf(buf, 256, CStr('[%c]'), 'Z');
  WRITELN(n);
  PutCStr(buf);

  { No tail arguments at all: the fixed prefix on its own still works. }
  n := snprintf(buf, 256, CStr('none'));
  WRITELN(n);
  PutCStr(buf);
END.
