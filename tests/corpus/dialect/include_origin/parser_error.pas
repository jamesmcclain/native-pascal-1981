{ A parser error inside an included file is located at the token where
  the parser stopped, in the included file's own lines, and names it. }
PROGRAM parser_error(OUTPUT);
(*$INCLUDE:'parser_error.inc'*)
BEGIN
  Greet
END.
