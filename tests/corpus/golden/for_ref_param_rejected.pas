{ DIALECT: vintage }
{ A FOR control variable cannot be a reference parameter, VAR or CONST,
  as the IBM manual says. Each use is a located typecheck error. }
PROGRAM for_ref_param_rejected(OUTPUT);
PROCEDURE pv(VAR i: INTEGER);
BEGIN
  FOR i := 1 TO 2 DO WRITELN(i)
END;
PROCEDURE pc(CONST i: INTEGER);
BEGIN
  FOR i := 1 TO 2 DO WRITELN(i)
END;
VAR k: INTEGER;
BEGIN
  pv(k)
END.
