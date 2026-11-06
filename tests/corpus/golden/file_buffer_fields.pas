{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ CMP-22: selectors on the buffer variable of a FILE OF a record: g^.a,
  nested records, arrays inside the record, WITH g^ DO, a VAR file formal,
  and a file of arrays of an anonymous record, read and assigned around
  PUT and GET. RANGECK checks a store to a subrange field and INDEXCK an
  index into an array field, as for any other record. }
PROGRAM FileBufferFields(OUTPUT);
{$RANGECK+}
{$INDEXCK+}
TYPE
  Digit = 0..9;
  Rec = RECORD
    a: INTEGER;
    d: Digit;
    name: ARRAY [1..3] OF CHAR;
    pos: RECORD
      x, y: INTEGER
    END
  END;
  RecFile = FILE OF Rec;
VAR
  g: RecFile;
  pairs: FILE OF ARRAY [1..2] OF RECORD k: INTEGER END;
  i, total: INTEGER;

PROCEDURE Fill(VAR f: RecFile; n: INTEGER);
VAR
  k: INTEGER;
BEGIN
  f^.a := n * 10;
  f^.d := n;
  FOR k := 1 TO 3 DO
    f^.name[k] := CHR(ORD('a') + n + k - 1);
  WITH f^.pos DO
  BEGIN
    x := n;
    y := -n
  END
END;

BEGIN
  REWRITE(g);
  FOR i := 1 TO 3 DO
  BEGIN
    Fill(g, i);
    PUT(g)
  END;
  WITH g^ DO
  BEGIN
    a := 99;
    d := 9;
    name[1] := 'x';
    name[2] := 'y';
    name[3] := 'z';
    pos.x := 7;
    pos.y := pos.x + 1
  END;
  PUT(g);
  RESET(g);
  total := 0;
  WHILE NOT EOF(g) DO
  BEGIN
    WRITELN(g^.a:1, ' ', g^.d:1, ' ', g^.name[1], g^.name[2], g^.name[3],
            ' (', g^.pos.x:1, ',', g^.pos.y:1, ')');
    total := total + g^.a + g^.pos.y;
    GET(g)
  END;
  WRITELN('total ', total:1);
  { Change one field of a component that was read and write it back. }
  RESET(g);
  i := g^.a;
  REWRITE(g);
  g^.a := i + 1;
  g^.pos.y := g^.a;
  WRITELN('rewritten ', g^.a:1, ' ', g^.pos.y:1);
  REWRITE(pairs);
  pairs^[1].k := 5;
  pairs^[2].k := pairs^[1].k * 2;
  PUT(pairs);
  RESET(pairs);
  WRITELN('pairs ', pairs^[1].k:1, ' ', pairs^[2].k:1)
END.
