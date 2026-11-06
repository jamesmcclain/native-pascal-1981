{ Included by codegen_boundary.pas. }
PROCEDURE Probe;
VAR s: LSTRING(4);
BEGIN
  {$INITCK+} WRITELN(SCANEQ(4, 'b', s, 1))
END;
