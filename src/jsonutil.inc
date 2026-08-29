{ INTERFACE header for jsonutil, the shared Str255/cJSON-node helper UNIT
  for the native pascal1981 stages (lexer.pas, parser.pas, typechecker.pas).
  Spliced via (*$INCLUDE:'jsonutil.inc'*) into every USES jsonutil caller,
  and into jsonutil.pas itself ahead of its IMPLEMENTATION. }

INTERFACE;
UNIT jsonutil (MakeCStr, CStrToStr255, CreateNode, AddField, AddStringField,
               AddIntField, AddRealField, AddBoolField, AddNullField,
               ParseJson, NodeType, GetObj, GetStr, GetInt, GetReal, GetBool,
               ArrSize, ArrItem, HasKey, EPrint, EPrintC, ReadAllStdin);

TYPE
  Str255     = LSTRING(255);
  CharBuf256 = ARRAY [0..255] OF CHAR;
  PCharBuf   = ^CharBuf256;

FUNCTION MakeCStr(s: Str255): ADRMEM;
FUNCTION CStrToStr255(ptr: ADRMEM): Str255;
FUNCTION CreateNode(type_name: Str255): ADRMEM;
PROCEDURE AddField(obj: ADRMEM; key_str: Str255; val_node: ADRMEM);
PROCEDURE AddStringField(obj: ADRMEM; key_str: Str255; val_str: Str255);
PROCEDURE AddIntField(obj: ADRMEM; key_str: Str255; val_int: INTEGER64);
PROCEDURE AddRealField(obj: ADRMEM; key_str: Str255; val_real: REAL);
PROCEDURE AddBoolField(obj: ADRMEM; key_str: Str255; val_bool: BOOLEAN);
PROCEDURE AddNullField(obj: ADRMEM; key_str: Str255);

FUNCTION ParseJson(text: ADRMEM): ADRMEM;
FUNCTION NodeType(obj: ADRMEM): Str255;
FUNCTION GetObj(obj: ADRMEM; key: Str255): ADRMEM;
FUNCTION GetStr(obj: ADRMEM; key: Str255): Str255;
FUNCTION GetInt(obj: ADRMEM; key: Str255): INTEGER32;
FUNCTION GetReal(obj: ADRMEM; key: Str255): REAL;
FUNCTION GetBool(obj: ADRMEM; key: Str255): BOOLEAN;
FUNCTION ArrSize(arr: ADRMEM): INTEGER32;
FUNCTION ArrItem(arr: ADRMEM; i: INTEGER32): ADRMEM;
FUNCTION HasKey(obj: ADRMEM; key: Str255): BOOLEAN;
PROCEDURE EPrint(msg: Str255);
PROCEDURE EPrintC(msg: ADRMEM);
FUNCTION ReadAllStdin: ADRMEM;

END;
