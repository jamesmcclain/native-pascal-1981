(*$INCLUDE:'program_module_shared_var.inc'*)
PROGRAM ProgramModuleSharedVar(OUTPUT);
USES modsharedvar;
VAR
  v: INTEGER;
BEGIN
  v := 10;
  BumpMod(32);
  WRITELN(v, ' ', GetMod);
END.
