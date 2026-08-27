PROGRAM BuiltinTypeShadowing(output);

{ The reproducer that used to typecheck as the built-in i16 WORD and then die
  in codegen. The manual makes a predeclared type name redefinable (p.3-7), so
  the user TYPE wins wherever the source names it, while STRING(16) -- carrying
  a param -- is still the built-in super array. }

TYPE
  WORD = LSTRING(64);
  BOOLEAN = RECORD
    x: INTEGER;
  END;
  STRING = RECORD
    tag: INTEGER;
  END;
  LSTRING = RECORD
    tag: INTEGER;
  END;

VAR
  current: WORD;
  flag: BOOLEAN;
  lrec: LSTRING;
  rec: STRING;
  s: STRING(16);
  n: INTEGER;

BEGIN
  current := 'shadowed';
  WRITELN(current);
  flag.x := 42;
  WRITELN(flag.x);
  lrec.tag := 9;
  WRITELN(lrec.tag);
  rec.tag := 7;
  WRITELN(rec.tag);
  s := 'still builtin   ';
  WRITELN(s);
  n := 3;
  IF n > 2 THEN
    WRITELN('IF still uses the predeclared BOOLEAN');
END.
