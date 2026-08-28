{ Statement parsing for the native parser. }

INTERFACE;
UNIT ps_stmt;
USES jsonutil, ps_base, ps_expr;

FUNCTION ParseWriteArg: ADRMEM;
FUNCTION ParseWriteArgList: ADRMEM;
FUNCTION ParseAssignOrCallStmt: ADRMEM;
FUNCTION ParseCompoundStmt: ADRMEM;
FUNCTION ParseCompoundStmtList: ADRMEM;
FUNCTION ParseIfStmt: ADRMEM;
FUNCTION ParseForStmt: ADRMEM;
FUNCTION ParseWhileStmt: ADRMEM;
FUNCTION ParseRepeatStmt: ADRMEM;
FUNCTION ParseCaseElement: ADRMEM;
FUNCTION ParseCaseStmt: ADRMEM;
FUNCTION ParseWithTarget: ADRMEM;
FUNCTION ParseWithStmt: ADRMEM;
FUNCTION ParseLabelStmt: ADRMEM;
FUNCTION ParseStatement: ADRMEM;

END;
