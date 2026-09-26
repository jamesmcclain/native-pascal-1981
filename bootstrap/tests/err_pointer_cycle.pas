{ Pointer types that only name each other never reach a real type. }
PROGRAM t;
TYPE P = ^Q; Q = ^P;
VAR x: P;
BEGIN END.
