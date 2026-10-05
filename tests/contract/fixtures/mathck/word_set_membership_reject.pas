PROGRAM WordSetMembershipReject;
VAR w: WORD; s: SET OF WORD;
BEGIN
  w := 40000; s := [];
  WRITELN(w IN s);
END.
