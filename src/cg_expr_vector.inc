{ Lowering for VECTOR [n] OF scalar operations: elementwise arithmetic and
  logic, VSPLAT, horizontal reductions, comparisons/masks/VSELECT, and
  VLOAD/VSTORE. Sits between cg_expr_literals and cg_expr in the codegen
  unit DAG -- it lowers already-evaluated operands (like cg_expr_sets) and
  never inspects or recursively evaluates an AST node; cg_expr evaluates
  the operands and dispatches in here from CodegenBinOp / CodegenUnaryOp /
  the FuncCall builtin ladder. }

INTERFACE;
UNIT cg_expr_vector;
USES jsonutil, features, cg_base, cg_util, cg_types;

{ VSPLAT(x, V): every lane of vector type vec_tid set to x. The caller has
  already evaluated x to scalar_val (type scalar_tk) and resolved the
  vector type name to vec_tid; arg_node is x's AST node, for diagnostics. }
FUNCTION CodegenVSplat(scalar_val: ADRMEM; scalar_tk: INTEGER; vec_tid: INTEGER; arg_node: ADRMEM): ADRMEM;

{ Elementwise `l <op> r` where both operands are the same VECTOR type. The
  caller (cg_expr's CodegenBinOp) has already evaluated the operands and
  passes their tracked type ids; op is the parser opcode string ('PLUS',
  'MINUS', 'MUL', 'SLASH', 'DIV', 'MOD', 'AND', 'OR', 'XOR'). }
FUNCTION CodegenVectorBinOp(op: Str255; lval, rval: ADRMEM; lvec_tid, rvec_tid: INTEGER): ADRMEM;

{ Elementwise unary `-v` ('MINUS') or `NOT v` ('NOT'). }
FUNCTION CodegenVectorUnaryOp(op: Str255; v: ADRMEM; vec_tid: INTEGER): ADRMEM;

END;
