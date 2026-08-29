{ .LEN belongs to LSTRING, which carries a length byte. A fixed STRING has no
  such byte, and naming .LEN on one is an error -- the same error as any other
  field selector on a non-record. (The reference compiler words it differently;
  what is pinned here is the rejection, not the phrasing.) }
PROGRAM LStringLenOnString(OUTPUT);
VAR
  s: STRING(20);
BEGIN
  WRITELN(ORD(s.LEN));
END.
