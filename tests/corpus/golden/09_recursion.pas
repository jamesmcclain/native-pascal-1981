PROGRAM RecursionTest(OUTPUT);

FUNCTION Fact(n: INTEGER): INTEGER;
BEGIN
  IF n <= 1 THEN
    Fact := 1
  ELSE
    Fact := n * Fact(n - 1);
END;

BEGIN
  WRITELN('Fact(5) = ', Fact(5));
END.
