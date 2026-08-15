(* should_pass: interface with no init block, terminated by a single END;.
   BASEPLOT form (was should_fail/15, which wrongly required a second END). *)
INTERFACE;
UNIT BASEPLOT (BLACK, WHITE, DRAWLINE);
TYPE RAINBOW = (BLACK, WHITE, RED, BLUE, GREEN);
PROCEDURE DRAWLINE (C: RAINBOW; H, V: INTEGER);
END;
