{ DIALECT: extended }
PROGRAM initstate;
TYPE Small = 1..3;
     Color = (Red, Green);
     Rec = RECORD field: INTEGER END;
VAR global_i: INTEGER;
FUNCTION supplied_result(supplied: INTEGER): INTEGER;
BEGIN supplied_result := supplied END;
PROCEDURE recurse(depth: INTEGER);
VAR x: INTEGER;
    b: BOOLEAN;
    c: CHAR;
    narrow: Small;
    shade: Color;
    r: REAL;
    wide: INTEGER32;
    p: ^INTEGER;
    recvar: Rec;
  PROCEDURE nested;
  VAR x: INTEGER;
  BEGIN x := 7 END;
BEGIN
  x := depth;
  b := TRUE;
  c := 'a';
  nested;
  IF depth > 0 THEN recurse(depth - 1)
END;
PROCEDURE sibling(supplied: INTEGER; VAR alias: INTEGER);
VAR x: INTEGER;
BEGIN x := supplied; alias := x END;
BEGIN
  recurse(2);
  recurse(1);
  sibling(4, global_i)
END.
