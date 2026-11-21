{ DIALECT: vintage extended }
{ NEW-37: WRD(0)..127 is a WORD subrange, so it cannot be assigned to an
  INTEGER variable without explicit narrowing. }
PROGRAM WordWrdSubrangeRejected;
VAR
  a: WRD(0)..127;
  i: INTEGER;
BEGIN
  a := WRD(5);
  i := a
END.
