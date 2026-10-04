PROGRAM SetBaseConstructorRejected(OUTPUT);
VAR
  s: SET OF 0..9;
BEGIN
  s := ['A', 1];
  s := [TRUE, 0];
  s := [1, TRUE];
  s := [TRUE..0];
  s := [1..TRUE];
  s := [TRUE..0, 1];
  s := [TRUE] + []
END.
