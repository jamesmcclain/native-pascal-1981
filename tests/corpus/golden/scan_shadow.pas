{ A user routine named SCANEQ shadows the builtin: user-routine dispatch. }
{ DIALECT: vintage extended }
PROGRAM shadow;
FUNCTION SCANEQ(x: INTEGER): INTEGER;
BEGIN SCANEQ := x + 1 END;
BEGIN WRITELN(SCANEQ(6)) END.
