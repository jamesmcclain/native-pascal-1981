PROGRAM boundary;
FUNCTION answer: REAL;
BEGIN answer := 1.0 {$INITCK+} END {$INITCK-};
BEGIN WRITELN(answer:3:1) END.
