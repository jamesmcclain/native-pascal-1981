{ DIALECT: extended }
{ DEVICE retains thin super-array pointers; no host descriptor ABI here. }
DEVICE INTERFACE;
UNIT DESCRIPTORTHIN (touch);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER32; PCells = ^Cells;
PROCEDURE touch(p: PCells);
END;
DEVICE IMPLEMENTATION OF DESCRIPTORTHIN;
PROCEDURE touch(p: PCells);
BEGIN p^[2] := 7 END;
.
