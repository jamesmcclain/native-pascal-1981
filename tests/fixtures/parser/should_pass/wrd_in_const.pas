(* 4.7: WRD in constant expressions — constant-folder path *)
(* NOTE: WRD(0)..127 as a *subrange bound* is a manual example (p.6-5) but  *)
(* requires the parser to accept a function call as a type-bound; that is a  *)
(* separate parser extension. This fixture covers the CONST-expression path  *)
(* that IS implemented in 4.7.                                               *)
PROGRAM WrdConst;
CONST
    ALLBITS = WRD(-1);    (* 0xFFFF — "same 16-bit value" rule, manual 11-8 *)
    HIBITS  = BYWORD(16#FF, 0);  (* 0xFF00 = 65280 *)
BEGIN
END.
