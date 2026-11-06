{ MIN DIV -1 in a constant overflows INTEGER64. }
PROGRAM p(input, output);
CONST MinI = -9223372036854775807 - 1; M1 = -1; Q = MinI DIV M1;
BEGIN
END.
