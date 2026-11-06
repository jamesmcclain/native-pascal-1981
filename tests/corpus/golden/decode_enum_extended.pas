{ DIALECT: extended }
{ OPT: 0 1 2 3 }
PROGRAM decode_enum_extended;
{ Extended READ accepts an enumerated value by name, without regard to
  letter case, or by ordinal, so DECODE does; a subrange keeps its bounds.
  The wide integers and REAL32 convert as READ converts them. }
{$RANGECK-}
TYPE color = (red, green, blue);
     warm = red..green;
VAR e: color; w: warm; b: BOOLEAN;
    i32: INTEGER32; i64: INTEGER64; w32: WORD32; w64: WORD64; i8: INTEGER8; w8: WORD8;
    r32: REAL32;
BEGIN
  e := red;
  WRITELN(DECODE('green', e), ' ', ORD(e));
  WRITELN(DECODE(' BLUE ', e), ' ', ORD(e));
  WRITELN(DECODE('0', e), ' ', ORD(e));
  WRITELN(DECODE('3', e), ' ', ORD(e));
  WRITELN(DECODE('purple', e), ' ', ORD(e));
  WRITELN(DECODE('green ish', e), ' ', ORD(e));
  w := red;
  WRITELN(DECODE('green', w), ' ', ORD(w));
  WRITELN(DECODE('blue', w), ' ', ORD(w));
  b := FALSE;
  WRITELN(DECODE('tRuE', b), ' ', b);
  i32 := 0;
  WRITELN(DECODE('-2147483648', i32), ' ', i32);
  WRITELN(DECODE('2147483648', i32), ' ', i32);
  i64 := 0;
  WRITELN(DECODE('9223372036854775807', i64), ' ', i64);
  WRITELN(DECODE('9223372036854775808', i64), ' ', i64);
  WRITELN(DECODE('-9223372036854775808', i64), ' ', i64);
  w32 := 0;
  WRITELN(DECODE('4294967295', w32), ' ', w32);
  WRITELN(DECODE('4294967296', w32), ' ', w32);
  w64 := 0;
  WRITELN(DECODE('18446744073709551615', w64), ' ', w64);
  WRITELN(DECODE('18446744073709551616', w64), ' ', w64);
  WRITELN(DECODE('-1', w64), ' ', w64);
  i8 := 0;
  WRITELN(DECODE('-128', i8), ' ', i8);
  WRITELN(DECODE('128', i8), ' ', i8);
  w8 := 0;
  WRITELN(DECODE('255', w8), ' ', w8);
  WRITELN(DECODE('256', w8), ' ', w8);
  r32 := 0.0;
  WRITELN(DECODE('1.5', r32), ' ', r32:6:2);
  WRITELN(DECODE('1.5.', r32), ' ', r32:6:2);
END.
