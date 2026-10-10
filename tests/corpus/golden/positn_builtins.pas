{ DIALECT: vintage extended }
{ OPT: 0 1 2 3 }
PROGRAM positn_builtins;
{$INITCK-}
TYPE Text2 = LSTRING(2); Text6 = LSTRING(6); TextPtr = ^Text6;
VAR p: Text2; s: Text6; fixed: STRING(6); calls: INTEGER;
    r: RECORD text: Text6 END; a: ARRAY [1..2] OF Text6; ptr: TextPtr;
FUNCTION Pattern: Text2;
BEGIN calls := calls * 10 + 1; Pattern := 'ab' END;
FUNCTION Source(n: INTEGER): Text6;
BEGIN calls := calls * 10 + 2; Source := 'ababab' END;
FUNCTION Position: INTEGER;
BEGIN calls := calls * 10 + 3; Position := 3 END;
FUNCTION EmptyPattern: Text2;
BEGIN calls := calls * 10 + 1; EmptyPattern := '' END;
PROCEDURE Formal(pat: Text2; CONST text: Text6; VAR mutable: Text6);
BEGIN WRITELN(POSITN(pat, text, 3), ' ', POSITN(pat, mutable, 4)) END;
BEGIN
  p := 'ab'; s := 'ababab'; fixed := 'ababab'; r.text := s; a[2] := s;
  WRITELN(POSITN(p, s, 1), ' ', POSITN(p, s, 2), ' ', POSITN(p, s, 4));
  WRITELN(POSITN('ab', fixed, 5), ' ', POSITN('ba', fixed, 6));
  WRITELN(POSITN('zz', s, 1), ' ', POSITN('abababa', s, 1));
  WRITELN(POSITN('ab', s, 0), ' ', POSITN('ab', s, -32768), ' ', POSITN('ab', s, 7), ' ', POSITN('ab', s, 32767));
  WRITELN(POSITN('', s, 1), ' ', POSITN('', s, 7), ' ', POSITN('', '', 0));
  WRITELN(POSITN('ab', '', 1), ' ', POSITN('a', 'ba', 1));
  WRITELN(POSITN('''', 'a''b', 1), ' ', positn('b', 'ababab', 3));
  WRITELN(POSITN(p, r.text, 3), ' ', POSITN(p, a[2], 3));
  calls := 0;
  WRITELN(POSITN(Pattern, Source(6), Position));
  WRITELN(calls);
  calls := 0;
  WRITELN(POSITN(Pattern(), Source(6), Position()));
  WRITELN(calls);
  calls := 0;
  WRITELN(POSITN(EmptyPattern, Source(6), Position));
  WRITELN(calls);
  Formal(p, s, r.text);
  NEW(ptr); ptr^ := s;
  WRITELN(POSITN(p, ptr^, 3));
  DISPOSE(ptr);
  WITH r DO WRITELN(POSITN(p, text, 3));
  WRITELN(POSITN('b', fixed, 6), ' ', POSITN('a', 'a', 1));
  s := 'ba'; p := '';
  WRITELN(POSITN('ab', s, 3), ' ', POSITN('ba', s, 1), ' ', POSITN(p, s, 7))
END.
