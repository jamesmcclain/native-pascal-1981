{ DIALECT: vintage extended }
{ CMP-19: a user declaration named INPUT or OUTPUT hides the predeclared
  file in its scope, as for any predeclared identifier (manual 3-7). The
  bare READ, EOF and WRITE forms still use standard input and output.
  INPUT is not in the heading: the predeclared files need no heading
  parameter (see docs/dialect_notes.md). }
PROGRAM PredeclaredFilesShadow(OUTPUT);
VAR
  input: INTEGER;
  n: INTEGER;

PROCEDURE Local;
VAR
  output: CHAR;
BEGIN
  output := 'z';
  WRITELN('local output = ', output)
END;

PROCEDURE Named;
{ Outside the local CHAR's scope, OUTPUT names the file again. }
BEGIN
  WRITELN(OUTPUT, 'named output')
END;

BEGIN
  input := 3;
  WRITELN('global input = ', input:1);
  Local;
  Named;
  READ(n);
  WRITELN('read ', n:1);
  IF NOT EOF THEN WRITELN('more')
END.
