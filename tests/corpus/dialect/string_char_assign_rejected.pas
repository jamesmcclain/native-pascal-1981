{ DIALECT: vintage extended }
{ NEW-33: CHAR converts automatically to LSTRING, not to fixed STRING(n). }
PROGRAM StringCharAssignRejected;
VAR
  s: STRING(10);
BEGIN
  s := 'a'
END.
