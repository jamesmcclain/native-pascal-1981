{ A CASE body is an ordinary statement and must be type checked like one.
  CheckStmt had no CaseStmt branch at all, so every case arm -- and the
  OTHERWISE arm -- skipped type checking entirely and reached codegen
  unexamined; this pins that they are walked, and that an arm still runs. }
PROGRAM CaseBodyTypechecked(output);
VAR
  i: INTEGER;
  total: INTEGER;
BEGIN
  total := 0;
  FOR i := 1 TO 4 DO
    CASE i OF
      1: total := total + 1;
      2, 3: total := total + 10
      OTHERWISE total := total + 100
    END;
  WRITELN(total)
END.
