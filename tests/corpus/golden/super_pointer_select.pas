{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ CMP-23: selection through a pointer element of a SUPER ARRAY reached
  through a pointer, l^[i]^.v, with INDEXCK and NILCK on. The typechecker's
  flat type metadata keeps three levels below a pointer; the record behind
  l^[i]^ is the fourth, and its fields are read back from the declared
  type. Reads, stores, nested records, arrays, a pointer chain, WITH, and
  deeper paths through a record field and an array of descriptors. }
PROGRAM SuperPointerSelect(OUTPUT);
{$INDEXCK+}
{$NILCK+}
TYPE
  PR = ^R;
  R = RECORD
    v: INTEGER;
    inner: RECORD
      w: INTEGER;
      tags: ARRAY [1..2] OF CHAR
    END;
    next: PR
  END;
  SA = SUPER ARRAY [0..*] OF PR;
  PSA = ^SA;
  TH = RECORD
    count: INTEGER;
    list: PSA
  END;
VAR
  l: PSA;
  h: ^TH;
  lists: ARRAY [1..2] OF PSA;
  i, sum: INTEGER;
BEGIN
  NEW(l, 2);
  FOR i := 0 TO 2 DO
  BEGIN
    NEW(l^[i]);
    l^[i]^.v := i * 3;
    l^[i]^.inner.w := 100 + i;
    l^[i]^.inner.tags[1] := 'a';
    l^[i]^.inner.tags[2] := CHR(ORD('0') + i);
    l^[i]^.next := NIL
  END;
  l^[0]^.next := l^[2];
  l^[0]^.next^.v := l^[0]^.next^.v + 1;
  WITH l^[1]^ DO
  BEGIN
    v := v + 10;
    inner.w := inner.w * 2
  END;
  sum := 0;
  FOR i := 0 TO 2 DO
  BEGIN
    WRITELN(i:1, ': ', l^[i]^.v:1, ' ', l^[i]^.inner.w:1, ' ',
            l^[i]^.inner.tags[1], l^[i]^.inner.tags[2]);
    sum := sum + l^[i]^.v
  END;
  WRITELN('sum ', sum:1, ' via next ', l^[0]^.next^.v:1);

  NEW(h);
  h^.count := 3;
  h^.list := l;
  h^.list^[2]^.v := 42;
  WRITELN('h ', h^.list^[2]^.v:1, ' ', h^.list^[1]^.inner.tags[2]);

  lists[1] := l;
  lists[2] := h^.list;
  lists[2]^[0]^.inner.w := -1;
  WRITELN('lists ', lists[1]^[0]^.inner.w:1, ' ', lists[2]^[2]^.v:1)
END.
