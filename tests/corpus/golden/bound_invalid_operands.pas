{ DIALECT: extended }
PROGRAM BoundInvalidOperands(output);
TYPE Data = SUPER ARRAY [0..*] OF INTEGER;
     PData = ^Data;
     Box = RECORD ptr: PData; fixed: ARRAY [1..2] OF INTEGER END;
VAR b: Box; p: PData;
BEGIN
  WRITELN(UPPER(b.missing^));
  WRITELN(LOWER(b.ptr));
  WRITELN(UPPER(b.fixed[1]));
  WRITELN(UPPER(p^[0]));
END.
