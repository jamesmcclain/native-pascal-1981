{ DIALECT: extended }
{ $RANGECK (on by default) checks stores into subranges; none of these is
  out of range, so none traps: assignment to a variable, a record field and
  an array element, a value parameter, a function result, READ of an
  INTEGER, CHAR and enumerated subrange, FOR loops that end on the declared
  bounds, and FOR loops that run zero times with out-of-range bounds. Under
  $RANGECK- an out-of-range store is not checked. }
PROGRAM SubrangeRangeChecksOk(input, output);
TYPE Digit = 0..9; Early = 'a'..'m'; Hue = (red, green, blue, cyan);
     Mid = green..blue; Sym = -5..5; Rec = RECORD d: Digit END;
VAR d: Digit; l: Early; m: Mid; s: Sym; r: Rec; a: ARRAY[1..3] OF Digit;
    i, n: INTEGER; t: TRUE..TRUE;
PROCEDURE P(x: Digit); BEGIN WRITELN('P ', x) END;
FUNCTION Next(x: INTEGER): Digit; BEGIN Next := x + 1 END;
BEGIN
  i := 7; d := i; r.d := 9; a[2] := d; s := -5; l := 'm'; m := blue; t := TRUE;
  P(d); d := Next(8);
  WRITELN(d, ' ', r.d, ' ', a[2], ' ', s, ' ', l, ' ', ORD(m), ' ', t);
  n := 0;
  FOR d := 0 TO 9 DO n := n + 1;
  FOR s := 5 DOWNTO -5 DO n := n + 1;
  FOR l := 'a' TO 'm' DO n := n + 1;
  FOR d := 20 TO 10 DO n := n + 100;
  FOR d := 3 DOWNTO 7 DO n := n + 100;
  WRITELN('iterations ', n);
  READLN(d, l); READLN(m);
  WRITELN(d, ' ', l, ' ', ORD(m));
  i := 10; {$RANGECK-} d := i; {$RANGECK+}
  WRITELN('unchecked ', ORD(d))
END.
