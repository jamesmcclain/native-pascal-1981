(*$INCLUDE:'vadd.inc'*)
PROGRAM host(output);
USES vaddu (add);
CONST n = 8;
VAR
  ha, hb, hc: ARRAY [0..7] OF INTEGER32;
  da, db, dc: ADRMEM;
  i: INTEGER;
  bytes: INTEGER;
BEGIN
  bytes := n * 4;
  FOR i := 0 TO n - 1 DO
  BEGIN
    ha[i] := i;
    hb[i] := i + i;
    hc[i] := 0
  END;
  da := DEVALLOC(bytes);
  db := DEVALLOC(bytes);
  dc := DEVALLOC(bytes);
  DEVCOPYTO(da, ADR ha, bytes);
  DEVCOPYTO(db, ADR hb, bytes);
  LAUNCH(add, 1, n, da, db, dc, n);
  DEVCOPYFROM(ADR hc, dc, bytes);
  FOR i := 0 TO n - 1 DO
    WRITELN(hc[i]);
  DEVFREE(da);
  DEVFREE(db);
  DEVFREE(dc)
END.
