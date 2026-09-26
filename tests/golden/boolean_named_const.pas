PROGRAM BooleanNamedConst(OUTPUT);
CONST Yes = TRUE;
      No = FALSE;
      AlsoYes = Yes;
VAR flag: BOOLEAN;
BEGIN
  flag := Yes;
  WRITELN('true ', flag, ' ', AlsoYes = TRUE);
  flag := No;
  WRITELN('false ', flag, ' ', No = FALSE)
END.
