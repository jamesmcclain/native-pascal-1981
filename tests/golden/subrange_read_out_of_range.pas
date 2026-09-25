{ DIALECT: extended }
{ READ of a CHAR subrange checks the character read. }
PROGRAM T(input, output);
TYPE Digit = 0..9; Early = 'a'..'m'; Hue = (red, green, blue, cyan);
     Mid = green..blue; Rec = RECORD d: Digit END;
VAR d: Digit; l: Early; m: Mid; r: Rec; i: INTEGER; h: Hue;
PROCEDURE P(x: Digit); BEGIN WRITELN('P ', x) END;
FUNCTION F(x: INTEGER): Digit; BEGIN F := x END;
BEGIN
  READLN(l); WRITELN('not reached ', l)
END.
