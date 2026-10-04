{ DIALECT: extended }
PROGRAM RejectFunctionArgument;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells; Q = ^Cells;
FUNCTION Source: Q;
BEGIN Source := NIL END;
PROCEDURE Sink(src: P);
BEGIN END;
BEGIN Sink(Source()) END.
