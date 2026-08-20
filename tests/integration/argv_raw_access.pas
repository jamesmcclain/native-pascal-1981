PROGRAM argv_raw_access(input, output);
{ The Pascal driver needs raw arguments, unlike PROGRAM heading parameters. }
FUNCTION pas_arg_count: CINT [C]; EXTERN;
FUNCTION pas_arg_value(index: CINT): ADRMEM [C]; EXTERN;
FUNCTION puts(text: ADRMEM): CINT [C]; EXTERN;
VAR
  count, result: CINT;
BEGIN
  count := pas_arg_count;
  WRITELN(count);
  result := puts(pas_arg_value(1));
END.
