PROGRAM scan_builtins;
{$INITCK-}
TYPE Text4 = LSTRING(4);
VAR s: Text4; fixed: STRING(4); calls: INTEGER;
    r: RECORD text: Text4 END;
FUNCTION Count: INTEGER;
BEGIN calls := calls * 10 + 1; Count := 4 END;
FUNCTION Pattern: CHAR;
BEGIN calls := calls * 10 + 2; Pattern := 'b' END;
FUNCTION Source: Text4;
BEGIN calls := calls * 10 + 3; Source := 'aaba' END;
FUNCTION Position: INTEGER;
BEGIN calls := calls * 10 + 4; Position := 1 END;
BEGIN
  s := 'aaba'; fixed := 'aaba'; calls := 0; r.text := s;
  WRITELN(SCANEQ(4, 'b', s, 1), ' ', SCANEQ(-4, 'b', s, 4));
  WRITELN(SCANNE(4, 'a', fixed, 1), ' ', SCANNE(-4, 'a', fixed, 4));
  WRITELN(SCANEQ(10, 'z', 'aaba', 1), ' ', SCANEQ(-10, 'z', s, 4));
  WRITELN(SCANNE(10, 'a', 'aa', 1), ' ', SCANNE(-10, 'a', 'aa', 2));
  WRITELN(SCANEQ(0, 'a', s, 1), ' ', SCANEQ(4, 'a', '', 1), ' ', SCANEQ(4, 'a', s, 5));
  WRITELN(SCANEQ(4, 'a', s, 1), ' ', SCANNE(4, 'b', s, 1));
  WRITELN(SCANEQ(Count, Pattern, Source, Position));
  WRITELN(calls);
  WRITELN(SCANEQ(4, 'b', r.text, 1))
END.
