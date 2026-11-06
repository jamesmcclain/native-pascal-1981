{ DIALECT: vintage extended }
{ BLT-15: a user declaration named EOF or EOLN shadows the niladic
  builtin. Standard input is empty, so the builtin EOLN would abort. }
PROGRAM NiladicEofShadow(INPUT, OUTPUT);

FUNCTION Eoln: BOOLEAN;
BEGIN
  Eoln := TRUE
END;

PROCEDURE Local;
VAR
  eof: INTEGER;
BEGIN
  eof := 7;
  WRITELN('local eof = ', eof:1)
END;

BEGIN
  Local;
  IF EOLN THEN WRITELN('user EOLN');
  IF EOF THEN WRITELN('builtin EOF')
END.
