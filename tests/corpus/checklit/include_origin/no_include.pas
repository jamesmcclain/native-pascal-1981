{ Without an include, no token or location carries a `file' field: the
  primary file's token JSON and AST are unchanged. }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-NOT: "file": }
{ CHECK: "location": }
PROGRAM no_include(OUTPUT);
VAR n: INTEGER;
BEGIN
  n := 1;
  WRITELN(n)
END.
