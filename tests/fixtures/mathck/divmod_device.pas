DEVICE INTERFACE;
UNIT safetydevice (divide);
PROCEDURE divide(a, b: INTEGER32);
END;
DEVICE IMPLEMENTATION OF safetydevice;
PROCEDURE divide(a, b: INTEGER32);
VAR c: INTEGER32;
BEGIN
  c := a DIV b
END;
.
