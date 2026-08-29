{ Statement-lowering declarations, shared with declaration lowering (a
  routine body is a statement list). Sits above expression and I/O
  lowering. }

INTERFACE;
UNIT cg_stmt;
USES jsonutil, features, cg_base, cg_util, cg_types, cg_symbols, cg_expr, cg_io;

FUNCTION IntToStr255(n: INTEGER32): Str255;
FUNCTION LabelKey(node: ADRMEM; key: Str255): Str255;
FUNCTION LookupLabel(name: Str255): INTEGER32;
PROCEDURE RegisterLabel(name: Str255);
PROCEDURE CollectLabelsArr(arr: ADRMEM);
PROCEDURE CollectLabels(stmt: ADRMEM);
PROCEDURE SetupFunctionLabels(body_arr: ADRMEM);
PROCEDURE CodegenStmtArray(arr: ADRMEM);
PROCEDURE CodegenAssignStmt(stmt: ADRMEM);
PROCEDURE CodegenIfStmt(stmt: ADRMEM);
PROCEDURE CodegenCaseStmt(stmt: ADRMEM);
PROCEDURE AttachUnrollHint(branch_inst: ADRMEM; count: INTEGER);
PROCEDURE CodegenWhileStmt(stmt: ADRMEM);
PROCEDURE CodegenRepeatStmt(stmt: ADRMEM);
PROCEDURE CodegenForStmt(stmt: ADRMEM);
PROCEDURE EmitByteCopyLoop(dest_ptr, src_ptr: ADRMEM; count: ADRMEM);
PROCEDURE EmitByteFillLoop(dest_ptr: ADRMEM; count: ADRMEM; fill_byte: INTEGER);
PROCEDURE CodegenCopylst(args: ADRMEM);
PROCEDURE CodegenCopystr(args: ADRMEM);
PROCEDURE CodegenInsert(args: ADRMEM);
PROCEDURE CodegenDelete(args: ADRMEM);
PROCEDURE CodegenConcat(args: ADRMEM);
FUNCTION EmitLaunchThunk(ridx: INTEGER32): ADRMEM;
FUNCTION LaunchRegistryPtr: ADRMEM;
FUNCTION DevicePtxPtr: ADRMEM;
FUNCTION LaunchThunkFor(ridx: INTEGER32): ADRMEM;
PROCEDURE EmitLaunchRegistry;
PROCEDURE CodegenLaunch(args: ADRMEM);
PROCEDURE CodegenDeviceSync(name: Str255);
FUNCTION CoerceToI8Ptr(v: ADRMEM; tk: INTEGER): ADRMEM;
PROCEDURE CodegenDeviceOrchestration(name: Str255; args: ADRMEM);
PROCEDURE CodegenProcCallStmt(stmt: ADRMEM);
PROCEDURE CodegenReturnStmt(stmt: ADRMEM);
FUNCTION FindLabeledLoopDepth(lbl: Str255): INTEGER32;
PROCEDURE CodegenBreakStmt(stmt: ADRMEM);
PROCEDURE CodegenCycleStmt(stmt: ADRMEM);
PROCEDURE CodegenGotoStmt(stmt: ADRMEM);
PROCEDURE CodegenLabelStmt(stmt: ADRMEM);
PROCEDURE CodegenWithStmt(stmt: ADRMEM);
PROCEDURE CodegenStmt(stmt: ADRMEM);

END;
