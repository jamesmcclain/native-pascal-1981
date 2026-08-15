(* should_pass: interface with proc/func headers and a BEGIN..END init block.
   GRAPHI form -- a single END terminates the (optional) init block and the
   interface together. Grammar: {BEGIN}- END ; *)
INTERFACE;
UNIT GRAPHICS (BJUMP, WJUMP);
USES OTHER;
PROCEDURE BJUMP (X, Y: INTEGER);
FUNCTION WJUMP (X, Y: INTEGER): INTEGER;
BEGIN
END;
