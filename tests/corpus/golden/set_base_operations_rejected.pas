PROGRAM SetBaseOperationsRejected(OUTPUT);
VAR
  s: SET OF 0..9;
  bs: SET OF BOOLEAN;
BEGIN
  s := s + bs;
  s := s - bs;
  s := s * bs;
  bs := bs + s;
  bs := bs - s;
  bs := bs * s;
  s := [TRUE] + [];
  s := [] + [TRUE];
  s := [TRUE] + [0]
END.
