{ IMPLEMENTATION of bytebuf. See bytebuf.inc for the contract and for the two
  dialect rules (16-bit bare INTEGER, pointers compare only with =/<>)
  that shape everything below. }

(*$INCLUDE:'bytebuf.inc'*)

IMPLEMENTATION OF bytebuf;

FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE free(p: ADRMEM) [C]; EXTERN;
FUNCTION memcpy(dst: ADRMEM; src: ADRMEM; n: CSIZE_T): ADRMEM [C]; EXTERN;

CONST
  MIN_CAP = 256;

{ ------------------------------------------------------------------ }
{ Lifecycle                                                           }
{ ------------------------------------------------------------------ }

PROCEDURE BufInit(VAR b: ByteBuf; initial_cap: INTEGER32);
VAR
  want: INTEGER32;
BEGIN
  want := initial_cap;
  IF want < MIN_CAP THEN want := MIN_CAP;
  b.data := malloc(want);
  b.len := 0;
  b.cap := want;
END;

PROCEDURE BufFree(VAR b: ByteBuf);
BEGIN
  IF b.data <> NIL THEN free(b.data);
  b.data := NIL;
  b.len := 0;
  b.cap := 0;
END;

PROCEDURE BufClear(VAR b: ByteBuf);
BEGIN
  b.len := 0;
END;

{ Grow to at least `need` bytes, doubling. The loop (rather than a single
  multiply) covers an append larger than the current capacity, where one
  doubling would not be enough. }
PROCEDURE BufReserve(VAR b: ByteBuf; need: INTEGER32);
VAR
  old: ADRMEM;
  newcap: INTEGER32;
BEGIN
  IF b.data = NIL THEN BufInit(b, need);
  IF need > b.cap THEN
  BEGIN
    newcap := b.cap;
    WHILE newcap < need DO newcap := newcap * 2;
    old := b.data;
    b.data := malloc(newcap);
    IF b.len > 0 THEN memcpy(b.data, old, RETYPE(CSIZE_T, b.len));
    free(old);
    b.cap := newcap;
  END;
END;

{ ------------------------------------------------------------------ }
{ Appending                                                           }
{ ------------------------------------------------------------------ }

PROCEDURE BufAppendChar(VAR b: ByteBuf; c: CHAR);
VAR
  base, p: ^CHAR;
BEGIN
  BufReserve(b, b.len + 1);
  base := b.data;
  p := base + b.len;
  p^ := c;
  b.len := b.len + 1;
END;

PROCEDURE BufAppendBytes(VAR b: ByteBuf; p: ADRMEM; n: INTEGER32);
VAR
  dst_base: ^CHAR;
  dst: ADRMEM;
BEGIN
  IF n > 0 THEN
  BEGIN
    BufReserve(b, b.len + n);
    dst_base := b.data;
    dst := dst_base + b.len;
    memcpy(dst, p, RETYPE(CSIZE_T, n));
    b.len := b.len + n;
  END;
END;

PROCEDURE BufAppendStr(VAR b: ByteBuf; s: ByteStr);
VAR
  i, n: INTEGER32;
BEGIN
  n := ORD(s[0]);
  i := 1;
  WHILE i <= n DO
  BEGIN
    BufAppendChar(b, s[i]);
    i := i + 1;
  END;
END;

PROCEDURE BufAppendCStr(VAR b: ByteBuf; p: ADRMEM);
VAR
  base, q: ^CHAR;
  i: INTEGER32;
BEGIN
  IF p <> NIL THEN
  BEGIN
    base := p;
    i := 0;
    q := base + i;
    WHILE q^ <> CHR(0) DO
    BEGIN
      BufAppendChar(b, q^);
      i := i + 1;
      q := base + i;
    END;
  END;
END;

PROCEDURE BufAppendBuf(VAR b: ByteBuf; VAR src: ByteBuf);
BEGIN
  IF src.len > 0 THEN BufAppendBytes(b, src.data, src.len);
END;

{ Decimal, no padding. Digits are produced least-significant first into a
  local array and then reversed, which avoids any recursion and any literal
  larger than ten. }
PROCEDURE BufAppendInt(VAR b: ByteBuf; v: INTEGER32);
VAR
  digits: ARRAY [0..31] OF CHAR;
  n, count, d: INTEGER32;
  negative: BOOLEAN;
BEGIN
  IF v = 0 THEN
    BufAppendChar(b, '0')
  ELSE
  BEGIN
    negative := v < 0;
    n := v;
    IF negative THEN n := -n;
    count := 0;
    WHILE n > 0 DO
    BEGIN
      d := n MOD 10;
      digits[count] := CHR(48 + RETYPE(INTEGER, d));
      n := n DIV 10;
      count := count + 1;
    END;
    IF negative THEN BufAppendChar(b, '-');
    WHILE count > 0 DO
    BEGIN
      count := count - 1;
      BufAppendChar(b, digits[count]);
    END;
  END;
END;

{ ------------------------------------------------------------------ }
{ Access                                                              }
{ ------------------------------------------------------------------ }

FUNCTION BufLen(VAR b: ByteBuf): INTEGER32;
BEGIN
  BufLen := b.len;
END;

FUNCTION BufPtr(VAR b: ByteBuf): ADRMEM;
BEGIN
  BufPtr := b.data;
END;

{ Writes the terminator past the end without counting it, so the buffer's
  length is unchanged and appending afterwards simply overwrites it. }
FUNCTION BufCStr(VAR b: ByteBuf): ADRMEM;
VAR
  base, p: ^CHAR;
BEGIN
  BufReserve(b, b.len + 1);
  base := b.data;
  p := base + b.len;
  p^ := CHR(0);
  BufCStr := b.data;
END;

FUNCTION BufAt(VAR b: ByteBuf; i: INTEGER32): CHAR;
VAR
  base, p: ^CHAR;
BEGIN
  IF (i < 0) OR (i >= b.len) THEN
    BufAt := CHR(0)
  ELSE
  BEGIN
    base := b.data;
    p := base + i;
    BufAt := p^;
  END;
END;

PROCEDURE BufSetAt(VAR b: ByteBuf; i: INTEGER32; c: CHAR);
VAR
  base, p: ^CHAR;
BEGIN
  IF (i >= 0) AND (i < b.len) THEN
  BEGIN
    base := b.data;
    p := base + i;
    p^ := c;
  END;
END;

PROCEDURE BufTruncate(VAR b: ByteBuf; new_len: INTEGER32);
BEGIN
  IF (new_len >= 0) AND (new_len < b.len) THEN b.len := new_len;
END;

{ ------------------------------------------------------------------ }
{ Searching and comparison                                            }
{ ------------------------------------------------------------------ }

FUNCTION BufIndexOfChar(VAR b: ByteBuf; c: CHAR; from: INTEGER32): INTEGER32;
VAR
  i, found: INTEGER32;
  base, p: ^CHAR;
BEGIN
  found := -1;
  i := from;
  IF i < 0 THEN i := 0;
  base := b.data;
  WHILE (i < b.len) AND (found < 0) DO
  BEGIN
    p := base + i;
    IF p^ = c THEN found := i;
    i := i + 1;
  END;
  BufIndexOfChar := found;
END;

FUNCTION BufMatchesStrAt(VAR b: ByteBuf; i: INTEGER32; s: ByteStr): BOOLEAN;
VAR
  j, n: INTEGER32;
  ok: BOOLEAN;
BEGIN
  n := ORD(s[0]);
  IF (i < 0) OR (i + n > b.len) THEN
    BufMatchesStrAt := FALSE
  ELSE
  BEGIN
    ok := TRUE;
    j := 1;
    WHILE (j <= n) AND ok DO
    BEGIN
      IF BufAt(b, i + j - 1) <> s[j] THEN ok := FALSE;
      j := j + 1;
    END;
    BufMatchesStrAt := ok;
  END;
END;

{ ASCII case folding only, which is all an HTTP header name needs. Written as
  arithmetic on ORD rather than a CASE with a range label, because this
  dialect's CASE takes neither ranges nor CHAR selectors. }
FUNCTION LowerOf(c: CHAR): CHAR;
VAR
  v: INTEGER;
BEGIN
  v := ORD(c);
  IF (v >= 65) AND (v <= 90) THEN v := v + 32;
  LowerOf := CHR(v);
END;

FUNCTION BufMatchesStrAtCI(VAR b: ByteBuf; i: INTEGER32; s: ByteStr): BOOLEAN;
VAR
  j, n: INTEGER32;
  ok: BOOLEAN;
BEGIN
  n := ORD(s[0]);
  IF (i < 0) OR (i + n > b.len) THEN
    BufMatchesStrAtCI := FALSE
  ELSE
  BEGIN
    ok := TRUE;
    j := 1;
    WHILE (j <= n) AND ok DO
    BEGIN
      IF LowerOf(BufAt(b, i + j - 1)) <> LowerOf(s[j]) THEN ok := FALSE;
      j := j + 1;
    END;
    BufMatchesStrAtCI := ok;
  END;
END;

FUNCTION BufIndexOfStr(VAR b: ByteBuf; s: ByteStr; from: INTEGER32): INTEGER32;
VAR
  i, n, limit, found: INTEGER32;
BEGIN
  n := ORD(s[0]);
  found := -1;
  IF n = 0 THEN
    found := from
  ELSE
  BEGIN
    i := from;
    IF i < 0 THEN i := 0;
    limit := b.len - n;
    WHILE (i <= limit) AND (found < 0) DO
    BEGIN
      IF BufMatchesStrAt(b, i, s) THEN found := i;
      i := i + 1;
    END;
  END;
  BufIndexOfStr := found;
END;

FUNCTION BufEqualsStr(VAR b: ByteBuf; s: ByteStr): BOOLEAN;
BEGIN
  IF b.len <> ORD(s[0]) THEN
    BufEqualsStr := FALSE
  ELSE
    BufEqualsStr := BufMatchesStrAt(b, 0, s);
END;

PROCEDURE BufSliceToStr(VAR b: ByteBuf; from: INTEGER32; count: INTEGER32;
                        VAR out: ByteStr);
VAR
  i, n: INTEGER32;
BEGIN
  n := count;
  IF n > 255 THEN n := 255;
  IF from + n > b.len THEN n := b.len - from;
  IF n < 0 THEN n := 0;
  out[0] := CHR(RETYPE(INTEGER, n));
  i := 1;
  WHILE i <= n DO
  BEGIN
    out[i] := BufAt(b, from + i - 1);
    i := i + 1;
  END;
END;

BEGIN
END.
