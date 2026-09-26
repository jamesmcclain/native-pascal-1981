PROGRAM forward_pointer_same_section(OUTPUT);
{ A forward pointer target must be declared in the same TYPE section; a
  VAR section in between ends it. }
TYPE
  P = ^N;
VAR x: P;
TYPE
  N = RECORD k: INTEGER END;
BEGIN
END.
