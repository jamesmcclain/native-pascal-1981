PROGRAM b(flag);
{ BOOLEAN is a type the manual permits as a program parameter (13-5: anything
  acceptable to READFN), but the native codegen's read dispatch does not
  implement it yet. Until it does, it must fail loudly at compile time
  rather than miscompile -- this negative fixture pins that. }
VAR
  flag: BOOLEAN;
BEGIN
  WRITELN(flag);
END.
