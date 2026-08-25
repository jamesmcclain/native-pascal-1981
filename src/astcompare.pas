{ Structural JSON comparator for frozen AST tests. Object key order is ignored;
  array order is significant. }
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM astcompare(input, output);

USES jsonutil;

FUNCTION pas_arg_count: CINT [C]; EXTERN;
FUNCTION pas_arg_value(index: CINT): ADRMEM [C]; EXTERN;
FUNCTION pas_read_text_file(path: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION pas_cjson_key(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION pas_cjson_child(item: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION strcmp(left, right: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetObjectItemCaseSensitive(obj, key: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetNumberValue(item: ADRMEM): REAL [C]; EXTERN;
FUNCTION cJSON_IsInvalid(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsFalse(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsTrue(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsNull(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsNumber(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsString(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsArray(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsObject(item: ADRMEM): CINT [C]; EXTERN;
PROCEDURE free(ptr: ADRMEM) [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;

CONST
  JSON_INVALID = 0;
  JSON_FALSE = 1;
  JSON_TRUE = 2;
  JSON_NULL = 3;
  JSON_NUMBER = 4;
  JSON_STRING = 5;
  JSON_ARRAY = 6;
  JSON_OBJECT = 7;
  MAX_COMPARE_DEPTH = 512;

VAR
  ignore_key: ADRMEM;
  compare_depth: INTEGER;

FUNCTION Join(left, right: Str255): Str255;
VAR
  result: Str255;
  i, left_len, right_len: INTEGER;
BEGIN
  left_len := ORD(left[0]);
  right_len := ORD(right[0]);
  IF left_len + right_len > 255 THEN right_len := 255 - left_len;
  result[0] := CHR(left_len + right_len);
  FOR i := 1 TO left_len DO result[i] := left[i];
  FOR i := 1 TO right_len DO result[left_len + i] := right[i];
  Join := result;
END;

FUNCTION CharString(ch: CHAR): Str255;
VAR
  result: Str255;
BEGIN
  result[0] := CHR(1);
  result[1] := ch;
  CharString := result;
END;

FUNCTION IntToStr(number: INTEGER32): Str255;
VAR
  result, reversed: Str255;
  digit, count, i: INTEGER;
  work: INTEGER32;
BEGIN
  IF number = 0 THEN result := CharString('0')
  ELSE BEGIN
    work := number;
    count := 0;
    WHILE work > 0 DO
    BEGIN
      count := count + 1;
      digit := RETYPE(INTEGER, work - (work DIV 10) * 10);
      reversed[count] := CHR(ORD('0') + digit);
      work := work DIV 10;
    END;
    result[0] := CHR(count);
    FOR i := 1 TO count DO result[i] := reversed[count - i + 1];
  END;
  IntToStr := result;
END;

FUNCTION NodeKind(item: ADRMEM): INTEGER;
BEGIN
  IF cJSON_IsObject(item) <> 0 THEN NodeKind := JSON_OBJECT
  ELSE IF cJSON_IsArray(item) <> 0 THEN NodeKind := JSON_ARRAY
  ELSE IF cJSON_IsString(item) <> 0 THEN NodeKind := JSON_STRING
  ELSE IF cJSON_IsNumber(item) <> 0 THEN NodeKind := JSON_NUMBER
  ELSE IF cJSON_IsTrue(item) <> 0 THEN NodeKind := JSON_TRUE
  ELSE IF cJSON_IsFalse(item) <> 0 THEN NodeKind := JSON_FALSE
  ELSE IF cJSON_IsNull(item) <> 0 THEN NodeKind := JSON_NULL
  ELSE NodeKind := JSON_INVALID;
END;

PROCEDURE Mismatch(path, detail: Str255);
BEGIN
  EPrint(Join(Join('Mismatch at ', path), Join(': ', detail)));
END;

FUNCTION IsIgnored(key: ADRMEM): BOOLEAN;
BEGIN
  IF ignore_key = NIL THEN IsIgnored := FALSE
  ELSE IsIgnored := strcmp(key, ignore_key) = 0;
END;

FUNCTION CompareNodes(expected, actual: ADRMEM; path: Str255): BOOLEAN;
VAR
  expected_kind, actual_kind: INTEGER;
  expected_size, actual_size, i: INTEGER32;
  expected_item, actual_item, key: ADRMEM;
  child_path: Str255;
  same: BOOLEAN;
BEGIN
  compare_depth := compare_depth + 1;
  IF compare_depth > MAX_COMPARE_DEPTH THEN
  BEGIN
    Mismatch(path, 'JSON nesting exceeds 512 levels');
    same := FALSE;
  END
  ELSE BEGIN
    expected_kind := NodeKind(expected);
    actual_kind := NodeKind(actual);
    IF expected_kind <> actual_kind THEN
    BEGIN
      Mismatch(path, 'JSON types differ');
      same := FALSE;
    END
    ELSE IF expected_kind = JSON_OBJECT THEN
    BEGIN
      same := TRUE;
      expected_size := ArrSize(expected);
      FOR i := 0 TO expected_size - 1 DO
      BEGIN
        expected_item := pas_cjson_child(expected, i);
        key := pas_cjson_key(expected_item);
        IF NOT IsIgnored(key) THEN
        BEGIN
          actual_item := cJSON_GetObjectItemCaseSensitive(actual, key);
          child_path := Join(Join(path, CharString('.')), CStrToStr255(key));
          IF actual_item = NIL THEN
          BEGIN
            Mismatch(child_path, 'key is missing from actual JSON');
            same := FALSE;
          END
          ELSE IF NOT CompareNodes(expected_item, actual_item, child_path) THEN
            same := FALSE;
        END;
      END;
      actual_size := ArrSize(actual);
      FOR i := 0 TO actual_size - 1 DO
      BEGIN
        actual_item := pas_cjson_child(actual, i);
        key := pas_cjson_key(actual_item);
        IF NOT IsIgnored(key) THEN
          IF cJSON_GetObjectItemCaseSensitive(expected, key) = NIL THEN
          BEGIN
            child_path := Join(Join(path, CharString('.')), CStrToStr255(key));
            Mismatch(child_path, 'unexpected key in actual JSON');
            same := FALSE;
          END;
      END;
    END
    ELSE IF expected_kind = JSON_ARRAY THEN
    BEGIN
      expected_size := ArrSize(expected);
      actual_size := ArrSize(actual);
      IF expected_size <> actual_size THEN
      BEGIN
        Mismatch(path, 'array lengths differ');
        same := FALSE;
      END
      ELSE BEGIN
        same := TRUE;
        FOR i := 0 TO expected_size - 1 DO
        BEGIN
          child_path := Join(Join(path, CharString('[')), Join(IntToStr(i), CharString(']')));
          IF NOT CompareNodes(ArrItem(expected, i), ArrItem(actual, i), child_path) THEN
            same := FALSE;
        END;
      END;
    END
    ELSE IF expected_kind = JSON_STRING THEN
    BEGIN
      same := strcmp(cJSON_GetStringValue(expected), cJSON_GetStringValue(actual)) = 0;
      IF NOT same THEN Mismatch(path, 'string values differ');
    END
    ELSE IF expected_kind = JSON_NUMBER THEN
    BEGIN
      same := cJSON_GetNumberValue(expected) = cJSON_GetNumberValue(actual);
      IF NOT same THEN Mismatch(path, 'number values differ');
    END
    ELSE
      same := TRUE;
  END;
  compare_depth := compare_depth - 1;
  CompareNodes := same;
END;

FUNCTION ReadJson(path: ADRMEM; label_name: Str255): ADRMEM;
VAR
  text, root: ADRMEM;
BEGIN
  text := pas_read_text_file(path);
  IF text = NIL THEN
  BEGIN
    EPrint(Join('astcompare: cannot read ', label_name));
    exit(1);
  END;
  root := ParseJson(text);
  free(text);
  IF root = NIL THEN
  BEGIN
    EPrint(Join('astcompare: malformed JSON in ', label_name));
    exit(1);
  END;
  ReadJson := root;
END;

PROCEDURE Usage;
BEGIN
  EPrint('Usage: astcompare [--ignore-key KEY] EXPECTED.json ACTUAL.json');
END;

VAR
  argc: CINT;
  expected_path, actual_path: ADRMEM;
  expected_root, actual_root: ADRMEM;

BEGIN
  argc := pas_arg_count;
  ignore_key := NIL;
  compare_depth := 0;
  IF argc = 3 THEN
  BEGIN
    expected_path := pas_arg_value(1);
    actual_path := pas_arg_value(2);
  END
  ELSE IF argc = 5 THEN
  BEGIN
    IF strcmp(pas_arg_value(1), MakeCStr('--ignore-key')) <> 0 THEN
    BEGIN
      Usage;
      exit(1);
    END;
    ignore_key := pas_arg_value(2);
    expected_path := pas_arg_value(3);
    actual_path := pas_arg_value(4);
  END
  ELSE BEGIN
    Usage;
    exit(1);
  END;

  expected_root := ReadJson(expected_path, 'expected file');
  actual_root := ReadJson(actual_path, 'actual file');
  IF CompareNodes(expected_root, actual_root, CharString('$')) THEN exit(0)
  ELSE exit(1);
END.
