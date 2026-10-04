{$RANGECK+}
PROGRAM Ranged;
TYPE Top = 32760..32767; Bottom = -32768..0;
VAR t: Top; b: Bottom; n, lo: INTEGER;
BEGIN
  lo := 32765;
  n := 0; FOR t := lo TO 32767 DO n := n + 1; WRITELN(n);
  n := 0; FOR t := 32767 DOWNTO 32760 DO n := n + 1; WRITELN(n);
  n := 0; FOR b := -32766 DOWNTO -32768 DO n := n + 1; WRITELN(n);
END.
