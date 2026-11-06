{ DIALECT: extended }
{ OPT: 0 2 }
PROGRAM LargeAggregateResults(output);
{ NEW-35: functions returning aggregates far past 65,535 bytes. clang used
  to crash at O0 on the whole-value copies of such a result (and was slow
  at every level); codegen now moves large aggregates with block copies.
  Covers LSTRING, STRING, ARRAY and RECORD results, a nested call, a result
  in an expression, in WRITE and as a value argument, and plain
  assignments between large variables. }
TYPE
  Big = LSTRING(70000);
  Fixed = STRING(70000);
  Vec = ARRAY [1..20000] OF INTEGER32;
  Rec = RECORD
          tag: INTEGER;
          data: ARRAY [1..70000] OF CHAR;
          tail: INTEGER;
        END;
VAR
  s, t: Big;
  f: Fixed;
  v: Vec;
  r: Rec;
  i: INTEGER32;

FUNCTION MakeBig(c: CHAR): Big;
BEGIN
  MakeBig := 'abc';
  MakeBig[2] := c;
END;

FUNCTION Wrap(c: CHAR): Big;
VAR
  inner: Big;
BEGIN
  inner := MakeBig(c);
  Wrap := inner;
END;

FUNCTION Nested(c: CHAR): Big;
BEGIN
  Nested := Wrap(c);
END;

FUNCTION MakeFixed: Fixed;
VAR
  k: INTEGER32;
  tmp: Fixed;
BEGIN
  FOR k := 1 TO 70000 DO tmp[k] := '.';
  tmp[1] := 'F';
  tmp[70000] := 'Z';
  MakeFixed := tmp;
END;

FUNCTION MakeVec(seed: INTEGER32): Vec;
VAR
  k: INTEGER32;
  tmp: Vec;
BEGIN
  FOR k := 1 TO 20000 DO tmp[k] := seed + k;
  MakeVec := tmp;
END;

FUNCTION MakeRec(n: INTEGER): Rec;
VAR
  tmp: Rec;
BEGIN
  tmp.tag := n;
  tmp.data[1] := 'r';
  tmp.data[70000] := 'q';
  tmp.tail := n + 1;
  MakeRec := tmp;
END;

FUNCTION LenOf(x: Big): INTEGER;
BEGIN
  LenOf := ORD(x.len);
END;

{$INITCK+}
PROCEDURE TrackedCopies;
{ INITCK-tracked large locals (30,000-byte records, INTEGER indexes as
  INITCK tracks them): whole copies carry the shadow state too, so an
  unset element would be reported at the copy, as for a small record. }
TYPE
  Tracked = RECORD
              tag: INTEGER;
              data: ARRAY [1..30000] OF CHAR;
            END;
VAR
  a, b, c: Tracked;
  k: INTEGER;
BEGIN
  a.tag := 1;
  FOR k := 1 TO 30000 DO a.data[k] := '-';
  a.data[3] := 'k';
  b := a;
  c := b;
  WRITELN(c.tag, ' ', c.data[3], c.data[30000]);
END;
{$INITCK-}

BEGIN
  s := MakeBig('x');
  WRITELN(s);
  WRITELN(MakeBig('y'));
  WRITELN(Nested('z'));
  t := s;
  s := Nested('w');
  WRITELN(t, ' ', s);
  IF MakeBig('x') = t THEN WRITELN('equal') ELSE WRITELN('differ');
  WRITELN(LenOf(Nested('q')));
  f := MakeFixed;
  WRITELN(f[1], f[2], f[70000]);
  v := MakeVec(100);
  WRITELN(v[1], ' ', v[20000]);
  r := MakeRec(7);
  WRITELN(r.tag, ' ', r.data[1], r.data[70000], ' ', r.tail);
  FOR i := 1 TO 3 DO
  BEGIN
    r := MakeRec(r.tail);
    WRITELN(r.tag);
  END;
  TrackedCopies;
END.
