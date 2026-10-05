{ DIALECT: extended }
PROGRAM InWideLeftRejected(OUTPUT);
VAR
  s: SET OF 0..9;
  w: INTEGER32;
BEGIN
  w := 3;
  WRITELN(w IN s)
END.
