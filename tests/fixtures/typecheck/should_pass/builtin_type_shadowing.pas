{ A user TYPE may shadow a predeclared type name and wins wherever the source
  names it (IBM Pascal, Aug 1981, p.3-7: predeclared identifiers "can be
  re-defined by the programmer"). STRING(n) carries a param and stays the
  built-in super-array constructor even here. Globbed by the reference-parity
  suite, so native and Python must agree on the typed AST. }
PROGRAM P;
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
  w: WORD;
  b: BOOLEAN;
  l: LSTRING;
  r: STRING;
  s: STRING(16);
  n: INTEGER;
BEGIN
  w := 'shadowed';
  b.x := 1;
  l.tag := 3;
  r.tag := 2;
  s := 'sixteen chars   ';
  n := 3
END.
