{ DIALECT: extended }
PROGRAM RejectDeviceLaunch;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
PROCEDURE kernel(src: PCells);
BEGIN END;
VAR p: PCells;
BEGIN p := NIL; LAUNCH(kernel, 1, 1, p) END.
