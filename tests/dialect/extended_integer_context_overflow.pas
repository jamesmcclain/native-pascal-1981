{ DIALECT: extended }
PROGRAM ExtendedIntegerContextOverflow;
VAR
  i8: INTEGER8;
  w8: WORD8;
  i32: INTEGER32;
  w32: WORD32;
BEGIN
  i8 := -129;
  i8 := 128;
  w8 := -1;
  w8 := 256;
  i32 := -2147483649;
  i32 := 2147483648;
  w32 := -1;
  w32 := 4294967296
END.
