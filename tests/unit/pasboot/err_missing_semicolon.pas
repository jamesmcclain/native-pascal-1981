{ Statements are separated by ";" (NEW-13): pasboot, like the native
  parser, rejects two statements run together. }
PROGRAM t; VAR i: INTEGER; BEGIN i := 1 i := 2 END.
