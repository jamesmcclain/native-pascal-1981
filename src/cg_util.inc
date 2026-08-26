{ Utility declarations shared by separately compiled codegen units. }

INTERFACE;
UNIT cg_util;
USES jsonutil, cg_base;

CONST
  MAX_EXPR_DEPTH = 64;
  MAX_STMT_DEPTH = 256;

VAR
  expr_depth, stmt_depth: INTEGER;

PROCEDURE AbortWith(msg: Str255);
PROCEDURE AbortWith2(prefix: Str255; suffix: Str255);
FUNCTION EntryAlloca(ty: ADRMEM; name: Str255): ADRMEM;
FUNCTION GetObjOrNil(obj: ADRMEM; key: Str255): ADRMEM;
PROCEDURE EnterExprLevel;
PROCEDURE LeaveExprLevel;
PROCEDURE EnterStmtLevel;
PROCEDURE LeaveStmtLevel;
FUNCTION DecodeStringLiteral(raw: Str255): Str255;
PROCEDURE AppendChar(VAR s: Str255; ch: CHAR);
FUNCTION UpperStr(s: Str255): Str255;
FUNCTION AllocPtrArray(n: INTEGER32): ADRMEM;
PROCEDURE SetPtrArrayElem(arr: ADRMEM; idx: INTEGER32; v: ADRMEM);
PROCEDURE EmitBlockCopy(dst: ADRMEM; src: ADRMEM; nbytes: INTEGER32);

END;
