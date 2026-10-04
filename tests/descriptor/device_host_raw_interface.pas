{ DIALECT: extended }
INTERFACE;
UNIT hostraw (RawData);
{ A private host descriptor type alone must not break an opaque raw API. }
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PrivateP = ^Cells;
FUNCTION RawData: CPTR;
END;
DEVICE INTERFACE;
UNIT deviceraw (touch);
PROCEDURE touch;
END;
DEVICE IMPLEMENTATION OF deviceraw;
USES hostraw;
PROCEDURE touch;
VAR raw: CPTR;
BEGIN raw := RawData() END;
.
