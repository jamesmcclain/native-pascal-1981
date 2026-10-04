{ DIALECT: extended }
PROGRAM ExtendedCAttributes(OUTPUT);
PROCEDURE c_one [C]; EXTERN;
PROCEDURE c_two [CDECL]; EXTERN;
PROCEDURE c_three [C, VARARGS]; EXTERN;
BEGIN
  WRITELN('extended C attributes ok')
END.
