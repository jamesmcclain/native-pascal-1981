{ DIALECT: extended }
{ Bare parameterless function names used as values: in arithmetic, a
  comparison, a recursive call inside the function's own
  body, and assignment to the result from within that body. }
PROGRAM BareFunctionValue(output);
VAR n, depth: INTEGER; w: INTEGER32; c: CHAR;
FUNCTION seven: INTEGER; BEGIN seven := 7 END;
FUNCTION big: INTEGER32; BEGIN big := 100000 END;
FUNCTION letter: CHAR; BEGIN letter := 'q' END;
FUNCTION countdown: INTEGER;
BEGIN
  IF depth = 0 THEN countdown := 0
  ELSE BEGIN depth := depth - 1; countdown := countdown + 1 END
END;
BEGIN
  n := seven * 2 + 1;
  w := big + 1;
  c := letter;
  depth := 5;
  WRITELN(n, ' ', w, ' ', c, ' ', seven > 6);
  WRITELN(countdown)
END.
