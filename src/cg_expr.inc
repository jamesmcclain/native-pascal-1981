{ Expression-lowering declarations shared by the codegen statement, I/O, and
  declaration units. This is the lowest lowering layer: it reads the symbol,
  type, and utility units below it and knows nothing about statements. }

INTERFACE;
UNIT cg_expr;
USES jsonutil, features, cg_base, cg_util, cg_types, cg_symbols;

PROCEDURE EmitSetRangeLoop(slot: ADRMEM; low_node, high_node: ADRMEM);
FUNCTION CodegenSetConstructor(node: ADRMEM): ADRMEM;
FUNCTION CodegenStringBinOp(op: Str255; left_node, right_node: ADRMEM): ADRMEM;
FUNCTION CodegenShortCircuitBinOp(op: Str255; left_node, right_node: ADRMEM): ADRMEM;
FUNCTION CodegenBinOp(op: Str255; left_node, right_node: ADRMEM): ADRMEM;
FUNCTION CodegenUnaryOp(op: Str255; operand_node: ADRMEM): ADRMEM;
FUNCTION CodegenCallCommon(name: Str255; args_arr: ADRMEM): ADRMEM;
FUNCTION ComputeDesignatorAddress(node: ADRMEM): ADRMEM;
{ The array operand of VLOAD/VSTORE: a bare array variable (Identifier) or
  any array-typed Designator (e.g. p^, r.buf). Returns its storage address;
  arr_tid is its type id and has_bound_hdr is TRUE only when the operand is
  the pointee of a plain ^T pointer in a non-DEVICE compiland -- the one
  shape where NEW's i64 upper-bound header sits 8 bytes before the data. }
FUNCTION VectorArrayOperand(node: ADRMEM; VAR arr_tid: INTEGER;
                            VAR has_bound_hdr: BOOLEAN): ADRMEM;
FUNCTION CodegenSimpleBuiltin(nm: Str255; args: ADRMEM): ADRMEM;
FUNCTION CodegenDevAlloc(args: ADRMEM): ADRMEM;
FUNCTION CodegenExpr(node: ADRMEM): ADRMEM;
PROCEDURE ResolveStringExprCharsLen(expr: ADRMEM; VAR chars_ptr: ADRMEM; VAR len_val: ADRMEM);
PROCEDURE ResolveStringDestVar(expr: ADRMEM; VAR d_symi: INTEGER32; VAR d_tid: INTEGER;
  VAR d_addr, chars_ptr, len_val: ADRMEM);
FUNCTION CodegenPositn(args: ADRMEM): ADRMEM;
FUNCTION CodegenScan(stop_on_equal: INTEGER; args: ADRMEM): ADRMEM;
FUNCTION CodegenEncode(args: ADRMEM): ADRMEM;
FUNCTION CodegenDecode(args: ADRMEM): ADRMEM;

END;
