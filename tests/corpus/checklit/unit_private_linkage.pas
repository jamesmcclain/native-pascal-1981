{ DIALECT: vintage extended }
{ CHECK: @Shared = global }
{ CHECK: @Exposed = }
{ CHECK: @Hidden = internal global }
{ CHECK: define i16 @GetIt( }
{ CHECK: define internal i16 @Helper( }
{ CHECK: define internal void @Later( }
{ CHECK: declare void @Elsewhere( }
{ CHECK: define i32 @pascal_init_linkunit( }
{ CHECK-NOT: @Exposed = internal }
{ CHECK: define void @Shown( }
{ CHECK-NOT: internal i16 @GetIt }
{ CHECK-ASSEMBLE: ir }
(* NEW-27: names an IMPLEMENTATION declares and its INTERFACE does not are
   private to the unit and get internal linkage; INTERFACE constituents,
   EXTERN declarations, [PUBLIC] names and the unit initializer keep
   external symbols. *)
INTERFACE;
UNIT LINKUNIT (Shared, GetIt);
VAR Shared: INTEGER;
FUNCTION GetIt: INTEGER;
END;
IMPLEMENTATION OF LINKUNIT;
VAR
  Shared, Hidden: INTEGER;
VAR [PUBLIC] Exposed: INTEGER;
PROCEDURE Elsewhere; EXTERN;
PROCEDURE Later; FORWARD;
PROCEDURE Shown [PUBLIC];
BEGIN
  Exposed := 1;
END;
FUNCTION Helper: INTEGER;
BEGIN
  Later;
  Helper := Hidden + 1;
END;
PROCEDURE Later;
BEGIN
  Hidden := 2;
END;
FUNCTION GetIt: INTEGER;
BEGIN
  Elsewhere;
  GetIt := Helper + Shared;
END;
BEGIN
END.
