(* should_fail: '$FF' dollar-hex is NOT part of the IBM Pascal 2.0 dialect.
   The manual radix form (16#FF) is the supported hexadecimal notation. *)
PROGRAM P;
CONST MASK = $FF;
BEGIN
END.
