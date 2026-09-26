PROGRAM forward_pointer_cycle(OUTPUT);
{ Pointer types that only name each other never reach a real type. }
TYPE
  P = ^Q;
  Q = ^P;
VAR x: P;
BEGIN
END.
