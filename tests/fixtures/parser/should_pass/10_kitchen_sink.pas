(* should_pass: broad valid program touching many productions. *)
PROGRAM DEMO;
CONST N = 10;
VAR   I : INTEGER;
      S : SET OF CHAR;
PROCEDURE BUMP(VAR X : INTEGER);
BEGIN
  X := X + 1
END;
BEGIN
  S := ['A'..'C', 'Z'];
  FOR I := 1 TO N DO BUMP(I);
  CASE I OF
    1..5: WRITELN('lo');
    OTHERWISE WRITELN('hi')
  END
END.
