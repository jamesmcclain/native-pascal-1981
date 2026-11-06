{ A RANGECK subrange store failing inside an included routine names the
  included file in the runtime diagnostic. }
PROGRAM runtime_subrange(OUTPUT);
TYPE Digit = 0..9;
VAR d: Digit;
(*$INCLUDE:'runtime_subrange.inc'*)
BEGIN
  WRITELN('start');
  Store(9);
  Store(10)
END.
