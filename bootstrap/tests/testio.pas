{ Output helpers for the pasboot fixtures; see testio.inc. }

(*$INCLUDE:'testio.inc'*)
IMPLEMENTATION OF testio;

TYPE
  Str255 = LSTRING(255);

VAR
  call_count: INTEGER32;

PROCEDURE WriteInt(n: INTEGER64);
VAR
  buf: ARRAY [1..24] OF CHAR;
  k: INTEGER;
  neg: BOOLEAN;
  d, v: INTEGER64;
BEGIN
  v := n;
  neg := v < 0;
  IF neg THEN
    v := -v;
  k := 0;
  WHILE TRUE DO
  BEGIN
    k := k + 1;
    d := v MOD 10;
    buf[k] := CHR(RETYPE(INTEGER, d) + 48);
    v := v DIV 10;
    IF v = 0 THEN
      BREAK;
  END;
  IF neg THEN
    WRITE('-');
  WHILE k > 0 DO
  BEGIN
    WRITE(buf[k]);
    k := k - 1;
  END;
END;

PROCEDURE WriteStr(s: Str255);
VAR
  i: INTEGER;
BEGIN
  FOR i := 1 TO ORD(s[0]) DO
    WRITE(s[i]);
END;

PROCEDURE WriteBool(b: BOOLEAN);
BEGIN
  IF b THEN
    WRITE('TRUE')
  ELSE
    WRITE('FALSE');
END;

PROCEDURE WriteLabel(s: Str255);
BEGIN
  WriteStr(s);
  WRITE(': ');
END;

PROCEDURE ReportCalls;
BEGIN
  WriteLabel('call_count');
  WriteInt(call_count);
  WRITELN;
END;

BEGIN
END.
