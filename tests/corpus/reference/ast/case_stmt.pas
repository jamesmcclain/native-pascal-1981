PROGRAM CaseTest(OUTPUT);

PROCEDURE TestVal(val: INTEGER);
BEGIN
  CASE val OF
    1: WRITELN('one');
    2, 3: WRITELN('two or three');
    OTHERWISE WRITELN('other: ', val)
  END;
END;

BEGIN
  TestVal(1);
  TestVal(3);
  TestVal(99);
END.
