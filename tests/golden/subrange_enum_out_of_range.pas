{ DIALECT: extended }
{ An enumeration value outside an enumerated subrange traps; the message
  reports ordinals. }
PROGRAM T(input, output);
TYPE Digit = 0..9; Early = 'a'..'m'; Hue = (red, green, blue, cyan);
     Mid = green..blue; Rec = RECORD d: Digit END;
VAR d: Digit; l: Early; m: Mid; r: Rec; i: INTEGER; h: Hue;
PROCEDURE P(x: Digit); BEGIN WRITELN('P ', x) END;
FUNCTION F(x: INTEGER): Digit; BEGIN F := x END;
BEGIN
  h := cyan; m := blue; WRITELN(ORD(m)); m := h
END.
