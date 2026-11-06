{ DIALECT: extended }
PROGRAM BoundExpressionStatic(output);
TYPE TS = SET OF 3..9;
     BoolSet = SET OF BOOLEAN;
     TE = (red, green, blue);
     TR = 3..9;
     Negative = -3..9;
     EnumRange = green..blue;
     BoolRange = FALSE..TRUE;
     Letters = 'a'..'z';
     TFixed = ARRAY [4..7] OF INTEGER;
     CharArray = ARRAY ['a'..'c'] OF INTEGER;
     EnumArray = ARRAY [red..blue] OF INTEGER;
     TBox = RECORD chars: CharArray END;
     Str = STRING(4);
     TLine = LSTRING(5);
     TV = VECTOR [4] OF INTEGER;
VAR s: TS; bs: BoolSet; e: TE; r: TR; neg: Negative;
    er: EnumRange; flag: BoolRange; letter: Letters;
    fixed: TFixed; ca: CharArray; ea: EnumArray; box: TBox;
    boxes: ARRAY [0..1] OF TBox;
    text: Str; line: TLine; v: TV;
    calls: INTEGER;
FUNCTION getset(n: INTEGER): TS;
BEGIN calls := calls + 1; getset := s END;
FUNCTION which(n: INTEGER): INTEGER;
BEGIN calls := calls + 1; which := 1 END;
BEGIN
  r := 4; er := green; flag := TRUE; letter := 'b';
  WRITELN(LOWER(s), ' ', UPPER(s));
  WRITELN(LOWER(bs), ' ', UPPER(bs));
  WRITELN(LOWER(bs + bs), ' ', UPPER(bs + bs));
  WRITELN(LOWER(getset(0)), ' ', UPPER(getset(0)), ' ', calls);
  WRITELN(LOWER(e), ' ', UPPER(green));
  WRITELN(LOWER(r), ' ', UPPER(r));
  WRITELN(LOWER(neg), ' ', UPPER(neg));
  WRITELN(LOWER(er), ' ', UPPER(er));
  WRITELN(LOWER(flag), ' ', UPPER(flag));
  WRITELN(LOWER(letter), ' ', UPPER(letter));
  WRITELN(LOWER(fixed), ' ', UPPER(fixed));
  WRITELN(LOWER(ca), ' ', UPPER(ca));
  WRITELN(LOWER(box.chars), ' ', UPPER(box.chars));
  WRITELN(LOWER(boxes[which(0)].chars), ' ',
          UPPER(boxes[which(0)].chars), ' ', calls);
  WRITELN(LOWER(ea), ' ', UPPER(ea));
  WRITELN(LOWER(text), ' ', UPPER(text));
  WRITELN(LOWER(line), ' ', UPPER(line));
  WRITELN(LOWER(v), ' ', UPPER(v));
  WRITELN(LOWER([1, 2]), ' ', UPPER([1, 2]))
END.
