PROGRAM Shape;
VAR i, lo, hi: INTEGER; w, wlo, whi: WORD; n: INTEGER;
BEGIN
  lo := 1; hi := 3; wlo := 1; whi := 3; n := 0;
  FOR i := lo TO hi DO n := n + 1;
  FOR w := whi DOWNTO wlo DO n := n + 1;
  WRITELN(n);
END.
