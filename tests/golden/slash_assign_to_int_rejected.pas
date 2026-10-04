PROGRAM SlashAssignToIntRejected(output);
{ Real division / produces REAL, so assigning its result to an INTEGER is rejected. }
VAR
  i: INTEGER;
BEGIN
  i := 4 / 2;
  WRITELN(i)
END.
