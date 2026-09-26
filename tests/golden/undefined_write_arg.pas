PROGRAM undefined_write_arg(OUTPUT);
{ An undefined first WRITELN argument is reported as undefined. Regression
  guard: the TEXT-file-selector probe indexed symbols[0] behind an eager AND,
  which the self-built typechecker's INDEXCK turned into a runtime abort. }
BEGIN
  WRITELN(zz)
END.
