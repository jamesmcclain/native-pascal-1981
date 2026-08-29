{ Shared token-stream state and AST primitives for the native parser. }

INTERFACE;
UNIT ps_base;
USES jsonutil;

{ C-FFI bindings to libcjson and standard C library routines }
FUNCTION cJSON_Parse(val: ADRMEM): ADRMEM [C];
FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C];
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C];
FUNCTION cJSON_GetObjectItem(obj: ADRMEM; key: ADRMEM): ADRMEM [C];
FUNCTION cJSON_CreateObject: ADRMEM [C];
FUNCTION cJSON_CreateArray: ADRMEM [C];
FUNCTION cJSON_CreateString(val: ADRMEM): ADRMEM [C];
FUNCTION cJSON_CreateNumber(num: REAL): ADRMEM [C];
FUNCTION cJSON_CreateBool(b: CINT): ADRMEM [C];
FUNCTION cJSON_CreateNull: ADRMEM [C];
PROCEDURE cJSON_AddItemToObject(obj: ADRMEM; key: ADRMEM; item: ADRMEM) [C];
PROCEDURE cJSON_AddItemToArray(arr: ADRMEM; item: ADRMEM) [C];
FUNCTION cJSON_Print(item: ADRMEM): ADRMEM [C];
PROCEDURE cJSON_Delete(item: ADRMEM) [C];
FUNCTION cJSON_Duplicate(item: ADRMEM; recurse: CINT): ADRMEM [C];
FUNCTION cJSON_DetachItemFromArray(arr: ADRMEM; which: CINT): ADRMEM [C];
FUNCTION cJSON_ReplaceItemInObject(obj: ADRMEM; key: ADRMEM; newitem: ADRMEM): CINT [C];

FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C];
FUNCTION cJSON_GetNumberValue(item: ADRMEM): REAL [C];
FUNCTION cJSON_IsNumber(item: ADRMEM): CINT [C];
FUNCTION cJSON_IsString(item: ADRMEM): CINT [C];
FUNCTION cJSON_IsTrue(item: ADRMEM): CINT [C];
FUNCTION puts(str: ADRMEM): CINT [C];
FUNCTION getchar: CINT [C];
FUNCTION malloc(size: CINT): ADRMEM [C];
PROCEDURE free(ptr: ADRMEM) [C];
PROCEDURE exit(code: CINT) [C];

CONST
  MAX_EXPR_DEPTH = 64;
  MAX_STMT_DEPTH = 256;
  MAX_TYPE_DEPTH = 128;

TYPE
  Token = RECORD
    kind: Str255;
    code: INTEGER32;
    lexeme: Str255;
    value_str: Str255;
    value_int: INTEGER64;
    value_real: REAL;
    value_type: INTEGER32;
    line: INTEGER32;
    col: INTEGER32;
    f_brave, f_debug, f_entry, f_goto, f_indexck, f_initck, f_line, f_list,
    f_mathck, f_nilck, f_ocode, f_rangeck, f_runtime, f_stackck, f_symtab,
    f_warn: BOOLEAN;
    has_unroll: BOOLEAN;
    unroll_val: INTEGER;
  END;
  PToken = ^Token;
  TokenBufArray = ARRAY [0..32000] OF Token;
  PTokenBufArray = ^TokenBufArray;

VAR
  tokens_buf: ADRMEM;
  num_tokens, pos: INTEGER32;
  expr_depth, stmt_depth, type_depth: INTEGER;

FUNCTION ReadBoolFlag(flags_json: ADRMEM; key_str: Str255): BOOLEAN;
PROCEDURE ReadInputAndParseTokens;
FUNCTION GetTok(off: INTEGER32): PToken;
FUNCTION CurKind: Str255;
FUNCTION CurLex: Str255;
FUNCTION CurValueInt: INTEGER64;
FUNCTION CurValueReal: REAL;
FUNCTION CurValueStr: Str255;
FUNCTION CurRangeCk: BOOLEAN;
FUNCTION CurHasUnroll: BOOLEAN;
FUNCTION CurUnrollVal: INTEGER;
FUNCTION BuildMetaFlagsNode: ADRMEM;
FUNCTION StrToIntVal(s: Str255): INTEGER;
FUNCTION StrToRealVal(s: Str255): REAL;
FUNCTION StringEqual(s1, s2: Str255): BOOLEAN;
FUNCTION UpperStr(s: Str255): Str255;
PROCEDURE Expect(k: Str255);
FUNCTION Match(k: Str255): BOOLEAN;
PROCEDURE EnterExprLevel;
PROCEDURE LeaveExprLevel;
PROCEDURE EnterStmtLevel;
PROCEDURE LeaveStmtLevel;
PROCEDURE EnterTypeLevel;
PROCEDURE LeaveTypeLevel;

END;
