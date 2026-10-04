{ DIALECT: extended }
INTERFACE;
UNIT hostdescriptor (PCells, Relay);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
FUNCTION Relay(src: PCells): PCells;
END;
DEVICE INTERFACE;
UNIT devicecaller (touch);
PROCEDURE touch;
END;
DEVICE IMPLEMENTATION OF devicecaller;
USES hostdescriptor;
PROCEDURE touch;
VAR p: PCells;
BEGIN p := NIL; p := Relay(p) END;
.
