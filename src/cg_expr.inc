{ Expression-lowering declarations shared by the codegen statement, I/O, and
  declaration units. This is the lowest lowering layer: it reads the symbol,
  type, and utility units below it and knows nothing about statements. }

INTERFACE;
UNIT cg_expr;
USES jsonutil, cg_base, cg_util, cg_types, cg_symbols;

PROCEDURE SetRuntimeBit(slot: ADRMEM; ordinal_val: ADRMEM);
PROCEDURE EmitSetRangeLoop(slot: ADRMEM; low_node, high_node: ADRMEM);
FUNCTION CodegenSetConstructor(node: ADRMEM): ADRMEM;
FUNCTION CodegenStringBinOp(op: Str255; left_node, right_node: ADRMEM): ADRMEM;
FUNCTION VariadicPromote(v: ADRMEM; tk: INTEGER; name: Str255): ADRMEM;
FUNCTION CodegenShortCircuitBinOp(op: Str255; left_node, right_node: ADRMEM): ADRMEM;
FUNCTION CodegenBinOp(op: Str255; left_node, right_node: ADRMEM): ADRMEM;
FUNCTION CodegenUnaryOp(op: Str255; operand_node: ADRMEM): ADRMEM;
FUNCTION CodegenCallCommon(name: Str255; args_arr: ADRMEM): ADRMEM;
FUNCTION ComputeDesignatorAddress(node: ADRMEM): ADRMEM;
PROCEDURE CodegenLStringLiteralAssign(dest_addr: ADRMEM; dest_tid: INTEGER; s: Str255);
PROCEDURE CodegenStringLiteralAssign(dest_addr: ADRMEM; dest_tid: INTEGER; s: Str255);
FUNCTION MakeArgs1(v: ADRMEM): ADRMEM;
FUNCTION CodegenSimpleBuiltin(nm: Str255; args: ADRMEM): ADRMEM;
FUNCTION CodegenHostDeviceIndex(nm: Str255): ADRMEM;
FUNCTION CodegenDeviceIndex(nm: Str255): ADRMEM;
FUNCTION CodegenDevAlloc(args: ADRMEM): ADRMEM;
FUNCTION CodegenExpr(node: ADRMEM): ADRMEM;
PROCEDURE ResolveStringExprCharsLen(expr: ADRMEM; VAR chars_ptr: ADRMEM; VAR len_val: ADRMEM);
PROCEDURE ResolveStringDestVar(expr: ADRMEM; VAR d_symi: INTEGER32; VAR d_tid: INTEGER;
  VAR d_addr, chars_ptr, len_val: ADRMEM);
FUNCTION CodegenPositn(args: ADRMEM): ADRMEM;
FUNCTION CodegenScan(stop_on_equal: INTEGER; args: ADRMEM): ADRMEM;
FUNCTION CodegenEncode(args: ADRMEM): ADRMEM;
FUNCTION CodegenDecode(args: ADRMEM): ADRMEM;
FUNCTION LaunchI64(v: ADRMEM; tk: INTEGER): ADRMEM;

END;
