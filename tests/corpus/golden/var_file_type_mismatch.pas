{ DIALECT: vintage extended }
PROGRAM VarFileTypeMismatch(OUTPUT);
{ TEXT sharing one type does not merge typed files: a FILE OF CHAR actual
  is not a VAR FILE OF INTEGER formal. }
TYPE
  IntF = FILE OF INTEGER;
  ChF = FILE OF CHAR;
VAR
  h: ChF;
PROCEDURE Numbers(VAR t: IntF);
BEGIN
  WRITELN('typed')
END;
BEGIN
  Numbers(h)
END.
