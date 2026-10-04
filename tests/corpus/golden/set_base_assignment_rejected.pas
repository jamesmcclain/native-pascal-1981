PROGRAM SetBaseAssignmentRejected(OUTPUT);
VAR
  s: SET OF 0..9;
  bs: SET OF BOOLEAN;
BEGIN
  s := ['A'];
  bs := [3];
  s := [TRUE];
  s := bs;
  bs := s
END.
