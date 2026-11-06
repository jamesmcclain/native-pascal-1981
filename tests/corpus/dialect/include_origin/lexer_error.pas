{ A lexer error inside an included file names that file: the location is
  the included file's own line and column, not the primary file's. }
PROGRAM lexer_error(OUTPUT);
(*$INCLUDE:'lexer_error.inc'*)
BEGIN
  WRITELN(big)
END.
