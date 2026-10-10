{ DIALECT: vintage extended }
{ OPT: 0 1 2 3 }
PROGRAM positn_capacity_boundary;
{$INITCK-}
VAR s: STRING(32767); p: STRING(32768); text: LSTRING(40000); j: INTEGER;
BEGIN
  FOR j := 1 TO 32767 DO BEGIN s[j] := 'a'; p[j] := 'a' END;
  s[32767] := 'b'; p[32768] := 'b'; text := 'abab';
  WRITELN(POSITN('b', s, 1), ' ', POSITN('b', s, 32767));
  WRITELN(POSITN(p, s, 1), ' ', POSITN('ab', text, 3))
END.
