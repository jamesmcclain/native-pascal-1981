(* judgment: same colon syntax on a non-write call. Almost certainly should
   be rejected, but the parser applies field-width to EVERY call. *)
PROGRAM P;
PROCEDURE FOO(a, b, c : INTEGER);
BEGIN
END;
BEGIN
  FOO(1:2:3)
END.
