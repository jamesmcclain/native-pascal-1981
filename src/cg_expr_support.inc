{ Leaf expression-lowering helpers.  This unit emits IR but never evaluates an
  AST node, so it remains below the expression dispatcher. }

INTERFACE;
UNIT cg_expr_support;
USES jsonutil, features, cg_base, cg_util, cg_types;

FUNCTION VariadicPromote(v: ADRMEM; tk: INTEGER; name: Str255): ADRMEM;
FUNCTION MakeArgs1(v: ADRMEM): ADRMEM;
FUNCTION CodegenHostDeviceIndex(nm: Str255): ADRMEM;
FUNCTION CodegenDeviceIndex(nm: Str255): ADRMEM;
FUNCTION LaunchI64(v: ADRMEM; tk: INTEGER): ADRMEM;
FUNCTION EnumNameTable(tid: INTEGER): ADRMEM;
PROCEDURE EmitScalarWriteArg(in_v: ADRMEM; tid: INTEGER; have_width, have_prec: BOOLEAN;
  width_val, prec_val: ADRMEM; VAR fmt: Str255; vals: ADRMEM; VAR vi: INTEGER32);
FUNCTION BoolNameTable: ADRMEM;
PROCEDURE SetOrdinalBoundArgs(call_args: ADRMEM; at, tid: INTEGER);

END;
