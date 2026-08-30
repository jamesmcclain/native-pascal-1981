{ Set operations that lower already-evaluated operands.  This unit is below
  cg_expr: it does not inspect or recursively evaluate expression nodes. }

INTERFACE;
UNIT cg_expr_sets;
USES jsonutil, features, cg_base, cg_util, cg_types, cg_symbols;

PROCEDURE SetRuntimeBit(slot: ADRMEM; ordinal_val: ADRMEM);
FUNCTION CodegenSetMember(ordinal_val, set_val: ADRMEM): ADRMEM;
FUNCTION CodegenSetBinOp(op: Str255; lval, rval: ADRMEM): ADRMEM;

END;
