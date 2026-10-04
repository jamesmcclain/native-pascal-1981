PROGRAM WordMembershipReject;
VAR w: WORD;
BEGIN
  w := 40000;
  WRITELN(w IN [0, 7, 255]);
END.
