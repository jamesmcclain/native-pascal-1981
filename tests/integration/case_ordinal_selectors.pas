{ DIALECT: extended }
{ A CASE selector may be any ordinal: every integer width, CHAR, BOOLEAN and
  an enumerated type. The labels are written as bare integer literals and
  named constants, so this also pins the label-to-selector width adaptation
  (an i16 INTEGER literal against an i32 or i64 selector, and a value past
  the 16-bit range in W32). Codegen accepted only INTEGER and CHAR before,
  and the typechecker did not look at CASE at all. }
PROGRAM CaseOrdinalSelectors(output);
TYPE
  COLOR = (RED, GREEN, BLUE);
CONST
  K_TWO = 2;
VAR
  i8: INTEGER8;
  i32: INTEGER32;
  i64: INTEGER64;
  w32: WORD32;
  c: CHAR;
  b: BOOLEAN;
  e: COLOR;
BEGIN
  i8 := 3;
  CASE i8 OF
    1: WRITELN('i8 wrong');
    3: WRITELN('i8 ok')
    OTHERWISE WRITELN('i8 otherwise')
  END;
  i32 := 2;
  CASE i32 OF
    1: WRITELN('i32 wrong');
    K_TWO: WRITELN('i32 ok')
    OTHERWISE WRITELN('i32 otherwise')
  END;
  i64 := 40000;
  CASE i64 OF
    40000: WRITELN('i64 ok')
    OTHERWISE WRITELN('i64 otherwise')
  END;
  w32 := 70000;
  CASE w32 OF
    70000: WRITELN('w32 ok')
    OTHERWISE WRITELN('w32 otherwise')
  END;
  c := 'q';
  CASE c OF
    'q': WRITELN('char ok')
    OTHERWISE WRITELN('char otherwise')
  END;
  b := FALSE;
  CASE b OF
    TRUE: WRITELN('bool wrong');
    FALSE: WRITELN('bool ok')
  END;
  e := BLUE;
  CASE e OF
    RED: WRITELN('enum wrong');
    BLUE: WRITELN('enum ok')
    OTHERWISE WRITELN('enum otherwise')
  END
END.
