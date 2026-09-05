{ Symbol and routine table declarations shared by codegen lowering units. }

INTERFACE;
UNIT cg_symbols;
USES jsonutil, features, cg_base, cg_util, cg_types;

FUNCTION LookupSym(name: Str255): INTEGER32;
FUNCTION LoadFileFcbPtr(name: Str255): ADRMEM;
PROCEDURE PushScope;
PROCEDURE PopScope;
FUNCTION CurScopeBase: INTEGER32;
PROCEDURE DeclareVar(name: Str255; tk: INTEGER);
PROCEDURE DeclareVarInSpace(name: Str255; tk, address_space: INTEGER);
FUNCTION RoutineIsFunc(routi: INTEGER32): BOOLEAN;
FUNCTION FuncRetAggClass(routi: INTEGER32): INTEGER;

END;
