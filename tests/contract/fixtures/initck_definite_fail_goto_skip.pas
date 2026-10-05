PROGRAM InitckDefiniteFail;
{$INITCK+}
PROCEDURE OneBranch;
VAR x, y: INTEGER;
BEGIN
  IF FALSE THEN x := 1;
  y := x;
  WRITELN('unreachable')
END;
PROCEDURE GotoSkip;
LABEL 1;
VAR x, y: INTEGER;
BEGIN
  GOTO 1;
  x := 1;
  1: y := x;
  WRITELN('unreachable')
END;
PROCEDURE ZeroLoop;
VAR x, y: INTEGER;
BEGIN
  WHILE FALSE DO x := 1;
  y := x;
  WRITELN('unreachable')
END;
PROCEDURE UncheckedCopy;
VAR x, y, unset: INTEGER;
BEGIN
  x := 1;
  {$INITCK-} x := unset; {$INITCK+}
  y := x;
  WRITELN('unreachable')
END;
FUNCTION Clobber(VAR dest: INTEGER): INTEGER;
VAR unset: INTEGER;
BEGIN
  {$INITCK-} dest := unset; {$INITCK+}
  Clobber := 1
END;
PROCEDURE CallEffect;
VAR x, y: INTEGER;
BEGIN
  x := 1;
  y := Clobber(x) + x;
  WRITELN('unreachable')
END;
BEGIN
  WRITELN('prefix');
  GotoSkip
END.
