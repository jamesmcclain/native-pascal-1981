{ DIALECT: vintage extended }
{ NEW-19: OTHERWISE takes a statement list, as the IBM manual's CASE
  statement allows, with ";" separating its statements as in BEGIN..END
  and an optional ";" before the CASE's END. }
PROGRAM CaseOtherwiseList(input, output);
VAR
  i, n, total: INTEGER;

FUNCTION Classify(k: INTEGER): INTEGER;
VAR
  r: INTEGER;
BEGIN
  CASE k OF
    1: r := 10;
    2: r := 20
    OTHERWISE
      r := k;
      r := r * 100;
      IF r > 500 THEN r := r + 1
  END;
  Classify := r
END;

BEGIN
  { Two statements, and a trailing ";" before END. }
  FOR i := 1 TO 3 DO
  BEGIN
    CASE i OF
      1: WRITELN('one');
    OTHERWISE
      WRITE('other ');
      WRITELN(i);
    END
  END;
  { One statement with a trailing ";". }
  CASE 7 OF
    1: WRITELN('no')
    OTHERWISE WRITELN('single');
  END;
  { An empty list, and empty statements among others. }
  CASE 5 OF
    5: WRITELN('five');
    OTHERWISE
  END;
  CASE 6 OF
    5: WRITELN('five')
    OTHERWISE ; WRITE('a'); ; WRITELN('b')
  END;
  { A nested CASE inside OTHERWISE, itself with a list. }
  FOR i := 1 TO 4 DO
    CASE i OF
      1: WRITELN('outer one');
    OTHERWISE
      WRITE('outer ');
      CASE i OF
        2: WRITELN('inner two');
      OTHERWISE
        WRITE('inner ');
        WRITELN(i)
      END;
      WRITELN('after inner')
    END;
  { In a function. }
  WRITELN(Classify(1), ' ', Classify(2), ' ', Classify(3), ' ',
    Classify(6));
  { In a REPEAT. }
  n := 0;
  total := 0;
  REPEAT
    n := n + 1;
    CASE n OF
      2: total := total + 1000;
    OTHERWISE
      total := total + n;
      WRITE(n)
    END
  UNTIL n = 4;
  WRITELN;
  WRITELN(total)
END.
