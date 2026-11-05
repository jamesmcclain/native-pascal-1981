{ DIALECT: vintage extended }
{ BLT-15: like a bare READ, niladic EOF and EOLN do not need INPUT in the
  program heading. The IBM manual warns there (6-27); native does not.
  See docs/dialect_notes.md, "Niladic EOF and EOLN". }
PROGRAM NiladicEofNoInputParam(OUTPUT);
VAR
  n: INTEGER;
BEGIN
  n := 0;
  WHILE NOT EOF DO
  BEGIN
    IF NOT EOLN THEN n := n + 1;
    READLN
  END;
  WRITELN(n:1)
END.
