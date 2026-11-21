{ DIALECT: vintage extended }
{ CHECK: @Hidden = internal global }
{ CHECK: @Exposed = }
{ CHECK-NOT: @Exposed = internal }
{ CHECK-ASSEMBLE: ir }
(* NEW-46: program-level globals get internal linkage unless marked [PUBLIC]. *)
PROGRAM ProgramPrivateLinkage(OUTPUT);
VAR
  Hidden: INTEGER;
VAR [PUBLIC]
  Exposed: INTEGER;
BEGIN
  Hidden := 1;
  Exposed := Hidden + 1;
  WRITELN(Exposed);
END.
