{ Native-only probe: compiler JSON lookups must be case-sensitive. }
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM JsonKeyCaseCheck(input, output);
USES jsonutil;
FUNCTION cJSON_CreateObject: ADRMEM [C]; EXTERN;
VAR flags, node: ADRMEM;
BEGIN
  { A read_flags/meta_flags object carries upper-case directive names. }
  flags := cJSON_CreateObject;
  AddBoolField(flags, 'INDEXCK', TRUE);
  AddBoolField(flags, 'MATHCK', TRUE);
  WRITELN(HasKey(flags, 'indexck'), ' ', GetBool(flags, 'indexck'));
  WRITELN(HasKey(flags, 'mathck'), ' ', GetBool(flags, 'mathck'));
  WRITELN(HasKey(flags, 'INDEXCK'), ' ', GetBool(flags, 'MATHCK'));
  { A selector/operator node carries the lower-case snapshot only. }
  node := cJSON_CreateObject;
  AddBoolField(node, 'indexck', FALSE);
  WRITELN(HasKey(node, 'INDEXCK'), ' ', HasKey(node, 'indexck'));
  WRITELN(NodeType(CreateNode('Probe')));
END.
