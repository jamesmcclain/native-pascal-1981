{ LSTRING's .LEN reached through an INDEX or a DEREF selector, not just off a
  bare variable. The aux2 marker that distinguishes an LSTRING from a fixed
  STRING has to survive ARRAY-element and pointer-base type resolution and the
  designator walk's INDEX/DEREF steps, or a[i].LEN / p^.LEN is rejected as a
  field selector on a non-record. Covers an array element (direct and via a
  TYPE alias), a pointer base, read and assignment position, and the lowercase
  spelling. Vintage dialect (IBM Pascal, Aug 1981). }
PROGRAM LStringLenIndirect(OUTPUT);
TYPE
  Row = ARRAY[1..3] OF LSTRING(12);
  PLine = ^LSTRING(12);
VAR
  a: ARRAY[1..3] OF LSTRING(12);
  r: Row;
  p: PLine;
BEGIN
  a[1] := 'abcde';
  WRITELN('array elem: ', ORD(a[1].LEN));

  a[2] := 'abcdefg';
  a[2].LEN := CHR(4);
  WRITELN('array elem truncated: ', a[2], ' (', ORD(a[2].LEN), ')');

  r[3] := 'hi';
  WRITELN('alias elem: ', ORD(r[3].len));

  NEW(p);
  p^ := 'wxyz';
  WRITELN('deref: ', ORD(p^.LEN));
  p^.LEN := CHR(1);
  WRITELN('deref truncated: ', p^, ' (', ORD(p^.LEN), ')');
END.
