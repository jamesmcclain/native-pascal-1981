{ Native-only AST probe: per-operation MATHCK snapshots are semantic, not
  reference-parser trivia. Prints one line per arithmetic operation or
  SUCC/PRED/ABS/SQR/VSUM/VPROD call in source tree order (parent before
  operands) and rejects a snapshot on any operation outside the MATHCK token
  scope. TRUNC/ROUND carry only an op_location for their always-on range
  check, never a MATHCK flag. }
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM MathckMetadataCheck(input, output);
USES jsonutil;
FUNCTION pas_cjson_child(item: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_IsObject(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsArray(item: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;
FUNCTION UpperName(s: Str255): Str255;
VAR i: INTEGER;
BEGIN
  FOR i := 1 TO ORD(s.LEN) DO
    IF (s[i] >= 'a') AND (s[i] <= 'z') THEN
      s[i] := CHR(ORD(s[i]) - ORD('a') + ORD('A'));
  UpperName := s;
END;
FUNCTION OpName(node: ADRMEM): Str255;
BEGIN
  IF NodeType(node) = 'FuncCall' THEN
    OpName := UpperName(GetStr(node, 'name'))
  ELSE IF HasKey(node, 'op') THEN
    OpName := GetStr(node, 'op')
  ELSE
    OpName := '';
END;
FUNCTION IsOperation(node: ADRMEM): BOOLEAN;
VAR nt: Str255;
BEGIN
  nt := NodeType(node);
  IsOperation := (nt = 'BinOp') OR (nt = 'UnaryOp') OR (nt = 'FuncCall');
END;
FUNCTION IsConversion(node: ADRMEM): BOOLEAN;
BEGIN
  IsConversion := (NodeType(node) = 'FuncCall') AND
    ((OpName(node) = 'TRUNC') OR (OpName(node) = 'ROUND'));
END;
FUNCTION InScope(node: ADRMEM): BOOLEAN;
VAR nt, op: Str255;
BEGIN
  nt := NodeType(node);
  op := OpName(node);
  IF nt = 'BinOp' THEN
    InScope := (op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') OR
      (op = 'DIV') OR (op = 'MOD')
  ELSE IF nt = 'UnaryOp' THEN
    InScope := op = 'MINUS'
  ELSE IF nt = 'FuncCall' THEN
    InScope := (op = 'SUCC') OR (op = 'PRED') OR (op = 'ABS') OR (op = 'SQR') OR
      (op = 'VSUM') OR (op = 'VPROD')
  ELSE
    InScope := FALSE;
END;
PROCEDURE Walk(node: ADRMEM);
VAR
  i, line, column: INTEGER32;
  location: ADRMEM;
  nt, op: Str255;
BEGIN
  IF cJSON_IsObject(node) <> 0 THEN
    IF InScope(node) THEN
    BEGIN
      IF NOT (HasKey(node, 'mathck') AND HasKey(node, 'op_location')) THEN
      BEGIN
        EPrint('missing per-operation MATHCK snapshot');
        exit(1);
      END;
      location := GetObj(node, 'op_location');
      line := GetInt(location, 'line');
      column := GetInt(location, 'column');
      nt := NodeType(node);
      op := OpName(node);
      WRITELN(nt, ' ', op, ' ', GetBool(node, 'mathck'), ' ', line:1, ':',
        column:1);
    END
    { Operator nodes only: cJSON key lookup ignores case, so every flags
      object's MATHCK entry would match 'mathck'. }
    ELSE IF IsConversion(node) AND
            (HasKey(node, 'mathck') OR NOT HasKey(node, 'op_location')) THEN
    BEGIN
      EPrint('TRUNC/ROUND must carry an op_location and no MATHCK snapshot');
      exit(1);
    END
    ELSE IF IsOperation(node) AND NOT IsConversion(node) AND
            (HasKey(node, 'mathck') OR HasKey(node, 'op_location')) THEN
    BEGIN
      EPrint('MATHCK snapshot on an out-of-scope node');
      exit(1);
    END;
  IF (cJSON_IsObject(node) <> 0) OR (cJSON_IsArray(node) <> 0) THEN
    FOR i := 0 TO ArrSize(node) - 1 DO Walk(pas_cjson_child(node, i));
END;
BEGIN
  Walk(ReadAllStdin);
END.
