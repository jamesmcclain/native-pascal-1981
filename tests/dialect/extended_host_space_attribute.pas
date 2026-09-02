{ DIALECT: extended }
PROGRAM ExtendedHostSpaceAttribute(output);
VAR
  [SPACE(SHARED)] scratch: ARRAY [0..7] OF INTEGER32;
BEGIN
  WRITELN('unreachable')
END.
