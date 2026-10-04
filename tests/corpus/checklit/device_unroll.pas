{ DEVICE code permits tuning hints independently of the CLI dialect. }
{ CHECK: llvm.loop.unroll.count }
DEVICE INTERFACE;
UNIT DUNROLL (spin);
PROCEDURE spin;
END;
DEVICE IMPLEMENTATION OF DUNROLL;
PROCEDURE spin;
VAR
  i: INTEGER32;
BEGIN
  i := 0;
  {$UNROLL 4}
  WHILE i < 4 DO
    i := i + 1
END;
.
