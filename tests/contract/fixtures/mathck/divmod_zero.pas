PROGRAM ZeroProbe;
FUNCTION LeftValue: {TYPE};
BEGIN WRITELN('left'); LeftValue := {LEFT} END;
FUNCTION RightValue: {TYPE};
BEGIN WRITELN('right'); RightValue := 0 END;
BEGIN
  WRITELN('prefix');
  WRITELN(LeftValue {OP} RightValue);
  WRITELN('unreachable')
END.
