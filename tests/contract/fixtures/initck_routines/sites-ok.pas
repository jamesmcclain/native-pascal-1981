PROGRAM sitesok;
FUNCTION restored: INTEGER; BEGIN {$PUSH} {$INITCK+} {$POP} END;
FUNCTION assigned(n: INTEGER): INTEGER;
BEGIN assigned := n; {$PUSH} {$INITCK+} RETURN {$POP} END;
BEGIN WRITELN(restored, ' ', assigned(3)) END.
