PROGRAM new_designator_not_pointer(OUTPUT);
{ A selected NEW/DISPOSE argument must still be a pointer. }
TYPE PN = ^N; N = RECORD v: INTEGER; next: PN END;
VAR q: PN;
BEGIN
  NEW(q); NEW(q^.v); DISPOSE(q^.v)
END.
