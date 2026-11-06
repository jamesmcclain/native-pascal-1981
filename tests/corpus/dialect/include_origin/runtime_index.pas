{ An INDEXCK failure inside an included routine names the included file in
  the runtime diagnostic. }
PROGRAM runtime_index(OUTPUT);
VAR a: ARRAY [1..3] OF INTEGER;
(*$INCLUDE:'runtime_index.inc'*)
BEGIN
  WRITELN('start');
  Store(4)
END.
