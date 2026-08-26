{ Declaration-lowering declarations: CONST/TYPE/VAR/LABEL, routine
  declarations and their bodies, USES clauses, and unit initialization.
  The top lowering layer -- nothing below it reaches back up. }

INTERFACE;
UNIT cg_decl;
USES jsonutil, cg_base, cg_util, cg_types, cg_symbols, cg_expr, cg_io, cg_stmt;

PROCEDURE CodegenDeclList(decls_arr: ADRMEM);
FUNCTION SameIdentifier(a, b: Str255): BOOLEAN;
FUNCTION FindUnitIndex(local_ifaces: ADRMEM; unit_name: Str255): INTEGER32;
PROCEDURE DFSVisitUnit(local_ifaces: ADRMEM; idx: INTEGER32);
PROCEDURE BuildUnitInitOrder(root, local_ifaces: ADRMEM);
PROCEDURE EmitUnitInitCalls;
PROCEDURE BindUsesAlias(alias, ename: Str255);
PROCEDURE CheckUsesClauses(root, local_ifaces: ADRMEM);
PROCEDURE InitFileStorage(slot: ADRMEM; elem_tid, structure: INTEGER; var_name: Str255);
PROCEDURE RegisterPredeclaredFiles;
PROCEDURE CodegenVarDecl(decl: ADRMEM);
PROCEDURE ApplyLaunchBoundAttrs(decl, fn: ADRMEM);
FUNCTION IsCForeignDecl(decl: ADRMEM): BOOLEAN;
FUNCTION IsVarargsDecl(decl: ADRMEM): BOOLEAN;
PROCEDURE FlattenParams(params_arr: ADRMEM; VAR n: INTEGER32; VAR names: ParamNameArr;
                         VAR tks: ParamTkArr; VAR isvar: ParamVarArr; VAR needs_copy: ParamVarArr);
FUNCTION ParamNamesOf(decl: ADRMEM; VAR names: ParamNameArr): INTEGER32;
FUNCTION ReadonlyBareFormal(node: ADRMEM): INTEGER32;
FUNCTION AssignWritesThroughFormal(node: ADRMEM): INTEGER32;
PROCEDURE ScanReadonlyNode(node: ADRMEM);
PROCEDURE ComputeReadonlyEffects(decl: ADRMEM);
FUNCTION LookupDevRoutine(name: Str255): INTEGER32;
PROCEDURE RegisterDevRoutines(decls: ADRMEM);
FUNCTION DeviceReadonlySummary(idx: INTEGER32; VAR ro: ParamVarArr): INTEGER32;
PROCEDURE ApplyKernelParamAttrs(decl, fn: ADRMEM; n: INTEGER32; VAR tks: ParamTkArr);
PROCEDURE CodegenRoutineDeclInner(decl: ADRMEM; is_func: BOOLEAN);
FUNCTION IsExternDirectiveDecl(decl: ADRMEM): BOOLEAN;
PROCEDURE CodegenRoutineDecl(decl: ADRMEM; is_func: BOOLEAN);
PROCEDURE CodegenTypeDecl(decl: ADRMEM);
PROCEDURE CodegenConstDecl(decl: ADRMEM);
PROCEDURE CodegenDecl(decl: ADRMEM);

END;
