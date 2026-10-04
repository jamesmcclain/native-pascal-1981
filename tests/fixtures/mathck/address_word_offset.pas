{ ^CHAR + WORD offsets 40000 and 32768 (either order), + 1, and ADRMEM +
  40000 read the right element: GEP offsets widen by their own
  signedness. The suite prepends MATHCK+ or MATHCK-. }
PROGRAM WordOffset(output);
VAR big: ARRAY [0..40001] OF CHAR; pc, base: ^CHAR; w: WORD; a: ADRMEM;
BEGIN
  base := ADR big;
  big[40000] := 'Z'; big[1] := 'a'; big[32768] := 'm';
  w := 40000; pc := base + w; WRITELN(pc^);
  w := 32768; pc := w + base; WRITELN(pc^);
  w := 1; pc := base + w; WRITELN(pc^);
  a := ADR big; a := a + 40000; pc := a; WRITELN(pc^)
END.
