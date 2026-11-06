{ DIALECT: vintage extended }
{ BLT-15: niladic EOLN at end of file is an error, as for EOLN(F)
  (manual 12-11). }
PROGRAM NiladicEolnAtEof(INPUT, OUTPUT);
BEGIN
  WRITELN('before');
  IF EOLN THEN WRITELN('eoln');
  WRITELN('after')
END.
