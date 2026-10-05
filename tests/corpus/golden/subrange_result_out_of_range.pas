{ DIALECT: extended }
{ Assigning a function's subrange result inside its body is checked. }
PROGRAM T(input, output);
TYPE Digit = 0..9; Early = 'a'..'m'; Hue = (red, green, blue, cyan);
     Mid = green..blue; Rec = RECORD d: Digit END;
VAR d: Digit; l: Early; m: Mid; r: Rec; i: INTEGER; h: Hue;
PROCEDURE P(x: Digit); BEGIN WRITELN('P ', x) END;
FUNCTION F(x: INTEGER): Digit; BEGIN F := x END;
BEGIN
  d := F(9); WRITELN(d); d := F(10)
END.
