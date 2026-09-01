{ Shared state and primitive operations for the native type checker. }

INTERFACE;
UNIT tc_base;
USES jsonutil, features;

CONST
  TK_UNKNOWN = 0;
  TK_INTEGER = 1;
  TK_REAL = 2;
  TK_BOOLEAN = 3;
  TK_CHAR = 4;
  TK_WORD = 5;
  TK_STRING = 6;
  TK_POINTER = 7;
  TK_ARRAY = 8;
  TK_RECORD = 9;
  TK_VOID = 10;
  TK_FILE = 11;
  TK_SET = 12;
  TK_ENUM = 13;
  TK_INTEGER8 = 14;
  TK_INTEGER32 = 15;
  TK_INTEGER64 = 16;
  TK_WORD8 = 17;
  TK_WORD32 = 18;
  TK_WORD64 = 19;
  TK_VECTOR = 20;
  { Keep this appended: stage-local ids are mirrored in codegen. }
  TK_REAL32 = 21;

  MAX_SYMBOLS = 2000;
  MAX_TYPES = 500;
  MAX_FIELDS = 2000;
  MAX_ERRORS = 200;
  MAX_PARAMS = 16;
  MAX_EXPR_DEPTH = 64;
  MAX_STMT_DEPTH = 256;

TYPE
  SymRec = RECORD
    name: Str255;
    kind: Str255;
    tk: INTEGER;
    aux: INTEGER;
    aux2: INTEGER;
    idx_tk: INTEGER;
    nparams: INTEGER;
    param_tk: ARRAY [1..MAX_PARAMS] OF INTEGER;
    ret_tk: INTEGER;
    is_vararg: BOOLEAN;
    is_extern: BOOLEAN;
    has_const_int: BOOLEAN;
    const_int: INTEGER64;
  END;

  TypeRec = RECORD
    name: Str255;
    tk: INTEGER;
    aux: INTEGER;
    aux2: INTEGER;
    idx_tk: INTEGER;
  END;

  FieldRec = RECORD
    record_id: INTEGER;
    fname: Str255;
    ftk: INTEGER;
    faux: INTEGER;
    faux2: INTEGER;
  END;

VAR
  symbols: ARRAY [1..MAX_SYMBOLS] OF SymRec;
  nsymbols: INTEGER32;
  scope_stack: ARRAY [1..64] OF INTEGER32;
  scope_top: INTEGER;
  types: ARRAY [1..MAX_TYPES] OF TypeRec;
  ntypes: INTEGER32;
  fields: ARRAY [1..MAX_FIELDS] OF FieldRec;
  nfields: INTEGER32;
  next_record_id: INTEGER;
  last_designator_aux, last_designator_aux2: INTEGER;
  errors: ARRAY [1..MAX_ERRORS] OF Str255;
  nerrors: INTEGER32;
  expr_depth, stmt_depth: INTEGER;
  cur_func_ret_tk: INTEGER;
  cur_func_aux, cur_func_aux2: INTEGER;
  cur_func_name: Str255;
  active_features: FeatureSet;
  is_device_compiland: BOOLEAN;

PROCEDURE TcInit(VAR requested_features: FeatureSet);
PROCEDURE AddError(msg: Str255);
PROCEDURE AddError2(msg: Str255; name: Str255);
FUNCTION UpperStr(s: Str255): Str255;
PROCEDURE PushScope;
PROCEDURE PopScope;
FUNCTION LookupSymbol(name: Str255): INTEGER32;
FUNCTION LookupSymbolInScope(name: Str255): INTEGER32;
FUNCTION DefineSymbol(name: Str255; kind: Str255; tk, aux, aux2, idx_tk: INTEGER): INTEGER32;
FUNCTION LookupType(name: Str255): INTEGER32;
FUNCTION GetObjOrNil(obj: ADRMEM; key: Str255): ADRMEM;
PROCEDURE AddFieldEntry(record_id: INTEGER; fname: Str255; ftk, faux, faux2: INTEGER);
FUNCTION LookupField(record_id: INTEGER; fname: Str255): INTEGER32;
PROCEDURE AddUniqueRecordField(record_id: INTEGER; fname: Str255; ftk, faux, faux2: INTEGER);
FUNCTION IsInteger(tk: INTEGER): BOOLEAN;
FUNCTION IsSignedInteger(tk: INTEGER): BOOLEAN;
FUNCTION IsUnsignedInteger(tk: INTEGER): BOOLEAN;
FUNCTION IntegerBits(tk: INTEGER): INTEGER;
FUNCTION IsOrdinal(tk: INTEGER): BOOLEAN;
FUNCTION IsNumeric(tk: INTEGER): BOOLEAN;
FUNCTION IsReal(tk: INTEGER): BOOLEAN;

END;
