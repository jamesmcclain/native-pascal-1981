{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Lexer Error: unrecognized character }
(* should_fail: '$' with no hex digits. *)
PROGRAM P;
CONST C = $;
BEGIN
END.
