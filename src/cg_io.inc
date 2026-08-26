{ WRITE/WRITELN/READ/READLN lowering declarations, shared by statement and
  declaration lowering. Sits directly above expression lowering. }

INTERFACE;
UNIT cg_io;
USES jsonutil, cg_base, cg_util, cg_types, cg_symbols, cg_expr;

FUNCTION EvalPrintfIntArg(node: ADRMEM): ADRMEM;
PROCEDURE EmitStringWriteArg(addr: ADRMEM; tid: INTEGER; have_width: BOOLEAN; width_val: ADRMEM;
  VAR fmt: Str255; vals: ADRMEM; VAR vi: INTEGER32);
PROCEDURE EmitScalarWriteArg(in_v: ADRMEM; tid: INTEGER; have_width, have_prec: BOOLEAN;
  width_val, prec_val: ADRMEM; VAR fmt: Str255; vals: ADRMEM; VAR vi: INTEGER32);
FUNCTION GetDefaultInputFcbPtr: ADRMEM;
PROCEDURE CodegenWriteArgs(args: ADRMEM; newline: BOOLEAN);
FUNCTION BoolNameTable: ADRMEM;
PROCEDURE CodegenReadStdinVar(addr: ADRMEM; tid: INTEGER);
PROCEDURE CodegenBindFileParameter(symi: INTEGER32);
PROCEDURE CodegenProgramParameters(root: ADRMEM);
PROCEDURE CodegenReadArgs(args: ADRMEM; is_readln: BOOLEAN);
PROCEDURE CodegenReadSet(args: ADRMEM);

END;
