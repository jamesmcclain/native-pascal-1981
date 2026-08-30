{ DEVICE compilands permit wide scalar types independently of CLI dialect. }
{ CHECK: define void @touch }
DEVICE INTERFACE;
UNIT DWIDE (touch);
PROCEDURE touch;
END;
DEVICE IMPLEMENTATION OF DWIDE;
PROCEDURE touch;
VAR
  i8: INTEGER8;
  i16: INTEGER16;
  i32: INTEGER32;
  i64: INTEGER64;
  w8: WORD8;
  w16: WORD16;
  w32: WORD32;
  w64: WORD64;
  r32: REAL32;
  r64: REAL64;
BEGIN
  w8 := WRD8(1)
END;
.
