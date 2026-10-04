{ DIALECT: extended }
{ Real division / produces REAL, so assigning its result to a REAL32 is
  rejected, the same as any other REAL into REAL32. }
PROGRAM SlashAssignToReal32Rejected(output);
VAR
  i: INTEGER;
  s: REAL32;
BEGIN
  i := 7;
  s := i;
  WRITELN(s:0:2);
  s := i / 2;
  WRITELN(s:0:2)
END.
