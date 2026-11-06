{ Included by parser_error.pas: the WHILE lacks its DO. }
PROCEDURE Greet;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE i < 2
    i := i + 1
END;
