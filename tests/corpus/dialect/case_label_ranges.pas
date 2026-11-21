{ NEW-38: CASE label ranges (lo..hi) across signed integers, high-bit WORD,
  CHAR, BOOLEAN, enumerations, mixed lists, and empty inverted ranges. }
PROGRAM CaseLabelRanges(OUTPUT);
TYPE
  Color = (Red, Orange, Yellow, Green, Blue);
VAR
  i: INTEGER;
  w: WORD;
  ch: CHAR;
  b: BOOLEAN;
  c: Color;

PROCEDURE TestInt(v: INTEGER);
BEGIN
  CASE v OF
    -10 .. -1: WRITELN('neg');
    0: WRITELN('zero');
    1, 3 .. 5, 9: WRITELN('mixed');
    20 .. 10: WRITELN('inverted');
    OTHERWISE
      WRITELN('other')
  END;
END;

PROCEDURE TestWord(v: WORD);
BEGIN
  CASE v OF
    0 .. 10: WRITELN('w_low');
    32768 .. 49999: WRITELN('w_mid');
    50000 .. 65535: WRITELN('w_high');
    OTHERWISE
      WRITELN('w_other')
  END;
END;

PROCEDURE TestChar(v: CHAR);
BEGIN
  CASE v OF
    '0' .. '9': WRITELN('digit');
    'A' .. 'Z': WRITELN('upper');
    'a' .. 'z': WRITELN('lower');
    OTHERWISE
      WRITELN('punct')
  END;
END;

PROCEDURE TestBool(v: BOOLEAN);
BEGIN
  CASE v OF
    FALSE .. TRUE: WRITELN('any_bool')
  END;
END;

PROCEDURE TestColor(v: Color);
BEGIN
  CASE v OF
    Red .. Yellow: WRITELN('warm');
    Green .. Blue: WRITELN('cool')
  END;
END;

BEGIN
  TestInt(-10);
  TestInt(-1);
  TestInt(0);
  TestInt(1);
  TestInt(4);
  TestInt(15);
  TestInt(2);

  TestWord(0);
  TestWord(32768);
  TestWord(49999);
  TestWord(65535);
  TestWord(20000);

  TestChar('5');
  TestChar('M');
  TestChar('z');
  TestChar('!');

  TestBool(FALSE);
  TestBool(TRUE);

  TestColor(Red);
  TestColor(Yellow);
  TestColor(Blue);
END.
