(* should_pass: uses_clause ends with an OPTIONAL ";" (grammar: ... [ ";" ]).
   Omitting it before the block is legal: program_unit = ";" [uses_clause] block ".".
   Current parser REJECTS this (unconditional expect SEMICOLON) -> known deviation. *)
PROGRAM P;
USES A
BEGIN
END.
