{ A CASE selector must be an ordinal value. The rejection now comes from the
  typechecker, with the rest of the compiland's errors, instead of from
  codegen one abort at a time. }
PROGRAM CaseSelectorNotOrdinal(OUTPUT);
VAR
  r: REAL;
BEGIN
  r := 1.0;
  CASE r OF
    1: WRITELN('one')
  END
END.
