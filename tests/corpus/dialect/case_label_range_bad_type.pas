{ NEW-38: CASE label range endpoints are typechecked against the selector. }
PROGRAM CaseLabelRangeBadType(OUTPUT);
VAR
  i: INTEGER;
BEGIN
  i := 1;
  CASE i OF
    'a' .. 'z': WRITELN('bad')
  END
END.
