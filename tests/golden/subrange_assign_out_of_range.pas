{ DIALECT: extended }
{ An INTEGER value outside 0..9 stored in a Digit record field traps. }
PROGRAM T(input, output);
TYPE Digit = 0..9; Early = 'a'..'m'; Hue = (red, green, blue, cyan);
     Mid = green..blue; Rec = RECORD d: Digit END;
VAR d: Digit; l: Early; m: Mid; r: Rec; i: INTEGER; h: Hue;
PROCEDURE P(x: Digit); BEGIN WRITELN('P ', x) END;
FUNCTION F(x: INTEGER): Digit; BEGIN F := x END;
BEGIN
  i := -1; WRITELN('before'); r.d := i; WRITELN('not reached')
END.
