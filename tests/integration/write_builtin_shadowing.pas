PROGRAM WriteBuiltinShadowing(output);
{ A user PROCEDURE WRITELN shadows the builtin. The parser WriteArg-wraps the
  actual arguments of anything spelled WRITE/WRITELN before any declaration is
  known, so the shadowed call has to see through that wrapper -- it used to
  typecheck and then abort in codegen with "unhandled expression kind:
  WriteArg". WRITE is left unshadowed here and still formats normally. }
VAR seen: INTEGER;

PROCEDURE WRITELN(v: INTEGER);
BEGIN
  seen := seen + v;
END;

BEGIN
  seen := 0;
  WRITELN(7);
  WRITELN(35);
  WRITE('seen=');
  WRITE(seen:3);
  WRITE(' done');
END.
