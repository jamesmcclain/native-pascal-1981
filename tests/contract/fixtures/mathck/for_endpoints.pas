PROGRAM ForEndpoints;
{ FOR loops terminate at the final value without stepping past it, at the
  type's extremes, in both directions, for every ordinal control type
  available in the vintage dialect. Iteration counts are the oracle; the
  post-loop control value is undefined and never printed. }
TYPE Color = (Red, Green, Blue);
VAR i, n, lo, hi: INTEGER;
    w, wlo, whi: WORD;
    c: CHAR;
    b: BOOLEAN;
    k: Color;
BEGIN
  { INTEGER: upper and lower extremes }
  n := 0; FOR i := 32765 TO 32767 DO n := n + 1; WRITELN('int to max ', n);
  n := 0; FOR i := -32766 DOWNTO -32768 DO n := n + 1; WRITELN('int downto min ', n);
  n := 0; FOR i := 32767 TO 32767 DO n := n + 1; WRITELN('int max once ', n);
  n := 0; FOR i := -32768 DOWNTO -32768 DO n := n + 1; WRITELN('int min once ', n);
  { INTEGER: zero-iteration and whole-range sign crossing }
  n := 0; FOR i := 5 TO 4 DO n := n + 1; WRITELN('int empty ', n);
  n := 0; FOR i := 4 DOWNTO 5 DO n := n + 1; WRITELN('int empty down ', n);
  n := 0; FOR i := -2 TO 2 DO n := n + 1; WRITELN('int cross zero ', n);
  { INTEGER: variable bounds, the limit is evaluated once }
  lo := 32760; hi := 32767;
  n := 0; FOR i := lo TO hi DO BEGIN n := n + 1; hi := 0 END; WRITELN('int var bounds ', n);
  { WORD: unsigned ordering across the sign bit and at both extremes }
  n := 0; FOR w := 32766 TO 32770 DO n := n + 1; WRITELN('word cross sign ', n);
  n := 0; FOR w := 65533 TO 65535 DO n := n + 1; WRITELN('word to max ', n);
  n := 0; FOR w := 2 DOWNTO 0 DO n := n + 1; WRITELN('word downto zero ', n);
  n := 0; FOR w := 65535 TO 65535 DO n := n + 1; WRITELN('word max once ', n);
  n := 0; FOR w := 0 DOWNTO 0 DO n := n + 1; WRITELN('word zero once ', n);
  n := 0; FOR w := 40000 TO 7 DO n := n + 1; WRITELN('word empty ', n);
  n := 0; FOR w := 7 DOWNTO 40000 DO n := n + 1; WRITELN('word empty down ', n);
  wlo := 40000; whi := 40002;
  n := 0; FOR w := wlo TO whi DO n := n + 1; WRITELN('word var high ', n);
  n := 0; FOR w := whi DOWNTO wlo DO n := n + 1; WRITELN('word var high down ', n);
  { CHAR and BOOLEAN keep their final-value exit }
  n := 0; FOR c := CHR(253) TO CHR(255) DO n := n + 1; WRITELN('char to max ', n);
  n := 0; FOR c := CHR(2) DOWNTO CHR(0) DO n := n + 1; WRITELN('char downto min ', n);
  n := 0; FOR b := FALSE TO TRUE DO n := n + 1; WRITELN('bool up ', n);
  n := 0; FOR b := TRUE DOWNTO FALSE DO n := n + 1; WRITELN('bool down ', n);
  { Enumerations reach their last and first members }
  n := 0; FOR k := Red TO Blue DO n := n + 1; WRITELN('enum up ', n);
  n := 0; FOR k := Blue DOWNTO Red DO n := n + 1; WRITELN('enum down ', n);
  n := 0; FOR k := Blue TO Red DO n := n + 1; WRITELN('enum empty ', n);
  { BREAK still exits the loop early }
  n := 0; FOR i := 32760 TO 32767 DO BEGIN n := n + 1; IF n = 3 THEN BREAK END;
  WRITELN('int break ', n);
END.
