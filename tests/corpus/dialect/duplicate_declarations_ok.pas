{ DIALECT: vintage extended }
{ NEW-7: what is not a duplicate declaration. A name may be declared again
  in an inner block (a parameter or local hides an outer declaration), a
  FORWARD heading is completed by the routine's body, and a user
  declaration may redefine a predeclared name (MAXINT, INPUT). }
PROGRAM DuplicateDeclarationsOk(OUTPUT);
CONST
  MAXINT = 5;
VAR
  input: INTEGER;
  x: INTEGER;

PROCEDURE later; FORWARD;

PROCEDURE p(x: CHAR);
VAR
  y: INTEGER;

  PROCEDURE inner;
  VAR
    y: CHAR;
  BEGIN
    y := 'i';
    WRITE(y)
  END;

BEGIN
  y := 1;
  inner;
  WRITELN(x, y)
END;

PROCEDURE later;
BEGIN
  WRITELN('later')
END;

FUNCTION f(n: INTEGER): INTEGER;
VAR
  x: INTEGER;
BEGIN
  x := n + 1;
  f := x
END;

BEGIN
  input := 3;
  x := MAXINT;
  p('c');
  later;
  WRITELN(f(x), ' ', input)
END.
