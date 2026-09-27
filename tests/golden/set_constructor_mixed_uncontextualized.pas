PROGRAM SetConstructorMixedUncontextualized(OUTPUT);
CONST Yes = TRUE;
TYPE Color = (red, blue); Shade = (light, dark);
VAR b: BOOLEAN;
FUNCTION Flag: BOOLEAN;
BEGIN Flag := Yes END;
BEGIN
  b := 0 IN ['A', 0];
  b := 1 IN [TRUE..0];
  b := 1 IN [1..FALSE];
  b := 0 IN [Flag, 0];
  b := red IN [red, light];
  b := 0 IN ([TRUE, 0] + []);
  WRITELN(b)
END.
