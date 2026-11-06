{ Utility declarations shared by separately compiled codegen units. }

INTERFACE;
UNIT cg_util;
USES jsonutil, features, cg_base;

CONST
  MAX_EXPR_DEPTH = 64;
  MAX_STMT_DEPTH = 256;
  { Up-level access: one frame per routine body being lowered. }
  MAX_FRAMES = 32;
  MAX_ENV_SLOTS = 256; { per frame }
  MAX_ENV_TOTAL = 8192; { MAX_FRAMES * MAX_ENV_SLOTS }
  MAX_CAPTURES = 1024;
  ENV_KEY_LINK = -1; { an environment slot holding the frame's static link }
  ENV_KEY_RESULT = -2; { ... a FUNCTION's result slot }
  ENV_KEY_RESULT_STATE = -3; { ... its INITCK result state }
  ENV_KEY_UPPER_BASE = -1000000; { ... minus symi: the UPPER slot of a
    captured conformant STRING/LSTRING formal (NEW-29) }

VAR
  expr_depth, stmt_depth: INTEGER;
  layout_line, layout_column: INTEGER32; { the declaration or statement
    being lowered, for LayoutTooLarge; 0 when none carries a location }
  { Up-level access (static links). frame_top routine bodies are being
    lowered, outermost first; frame 1 is a compiland-level routine. A frame's
    symbols are symbols[frame_sym_base + 1 ..]. A nested routine takes its
    parent frame's environment, an array of pointers built in the parent's
    entry block, as its hidden last parameter (frame_link). env_slot_*
    holds each frame's slots, MAX_ENV_SLOTS per frame. A capture caches,
    per frame, the pointer an up-level name resolves to in that routine
    (loaded before frame_anchor in its entry block); a captured symbol's
    llvm_val is swapped for it until the frame closes. }
  frame_top: INTEGER32;
  frame_fn, frame_link, frame_anchor, frame_env: ARRAY [1..MAX_FRAMES] OF ADRMEM;
  frame_name, frame_func_name: ARRAY [1..MAX_FRAMES] OF Str255;
  frame_sym_base, frame_nslots: ARRAY [1..MAX_FRAMES] OF INTEGER32;
  frame_ret_slot, frame_ret_state: ARRAY [1..MAX_FRAMES] OF ADRMEM;
  frame_ret_tk: ARRAY [1..MAX_FRAMES] OF INTEGER;
  env_slot_key: ARRAY [1..MAX_ENV_TOTAL] OF INTEGER32;
  env_slot_val: ARRAY [1..MAX_ENV_TOTAL] OF ADRMEM;
  ncaptures: INTEGER32;
  capture_frame, capture_owner, capture_key: ARRAY [1..MAX_CAPTURES] OF INTEGER32;
  capture_val, capture_old: ARRAY [1..MAX_CAPTURES] OF ADRMEM;
  capture_suspended: BOOLEAN; { TRUE while a pass only resolves names and
    emits no code through them (PrepareInitckLocals): no capture is made,
    so a rejected one is reported where the code uses it }

PROCEDURE AbortWith(msg: Str255);
PROCEDURE AbortWith2(prefix: Str255; suffix: Str255);
PROCEDURE AbortAtLayoutSite(msg: Str255);
PROCEDURE LayoutTooLarge;
FUNCTION LayoutBytes(wide: INTEGER64): INTEGER32;
PROCEDURE EnterLayoutSite(node: ADRMEM; VAR saved_line, saved_column: INTEGER32);
PROCEDURE LeaveLayoutSite(saved_line, saved_column: INTEGER32);
FUNCTION IntToStr255(n: INTEGER32): Str255;
FUNCTION EntryAlloca(ty: ADRMEM; name: Str255): ADRMEM;
FUNCTION GetObjOrNil(obj: ADRMEM; key: Str255): ADRMEM;
PROCEDURE EnterExprLevel;
PROCEDURE LeaveExprLevel;
PROCEDURE EnterStmtLevel;
PROCEDURE LeaveStmtLevel;
FUNCTION DecodeStringLiteral(raw: Str255): Str255;
PROCEDURE AppendChar(VAR s: Str255; ch: CHAR);
FUNCTION UpperStr(s: Str255): Str255;
FUNCTION LookupConst(name: Str255): INTEGER32;
FUNCTION CurConstScopeBase: INTEGER32;
FUNCTION LookupSym(name: Str255): INTEGER32;
FUNCTION LookupRoutine(name: Str255): INTEGER32;
FUNCTION UserRoutineShadows(name: Str255): BOOLEAN;
FUNCTION IsPredeclaredMaximum(uname: Str255): BOOLEAN;
FUNCTION PredeclaredConstVisible(name: Str255): BOOLEAN;
FUNCTION UserDeclarationHides(name: Str255): BOOLEAN;
FUNCTION IsDeviceIndexName(uname: Str255): BOOLEAN;
FUNCTION DeviceIndexVisible(name: Str255): BOOLEAN;
FUNCTION AllocPtrArray(n: INTEGER32): ADRMEM;
PROCEDURE SetPtrArrayElem(arr: ADRMEM; idx: INTEGER32; v: ADRMEM);
FUNCTION InitckPendingAt(i: INTEGER32): PInitckPending;
PROCEDURE InitckQueueRelease(p: ADRMEM; tid: INTEGER);
PROCEDURE EmitBlockCopy(dst: ADRMEM; src: ADRMEM; nbytes: INTEGER32);
FUNCTION LargeAggregateTy(ty: ADRMEM): BOOLEAN;
PROCEDURE LowerLargeAggregateCopies;
PROCEDURE AppendText(VAR s: Str255; t: Str255);
FUNCTION CgElide(s: Str255; maxlen: INTEGER): Str255;
FUNCTION BoundedSymbol(a, b: Str255): Str255;
PROCEDURE AppendLocation(VAR msg: Str255; location: ADRMEM);
PROCEDURE EmitDiagFile(location: ADRMEM);
FUNCTION NodeDiagLocation(node: ADRMEM): ADRMEM;
PROCEDURE OpenFrame(fn: ADRMEM; name: Str255; link: ADRMEM);
PROCEDURE SetFrameResult(func_name: Str255; ret_tk: INTEGER; slot, state: ADRMEM);
PROCEDURE CloseFrame;
FUNCTION FrameEnvFor(d: INTEGER32; callee: Str255): ADRMEM;
FUNCTION CapturedFramePtr(d, key: INTEGER32; val: ADRMEM; what: Str255): ADRMEM;
FUNCTION EnclosingResultFrame(name: Str255): INTEGER32;

END;
