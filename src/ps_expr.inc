{ Expression, constant, selector, and type parsing for the native parser. }

INTERFACE;
UNIT ps_expr;
USES jsonutil, ps_base;

FUNCTION ParseIdentifier: ADRMEM;
FUNCTION ParseDesignatorRest(name: Str255): ADRMEM;
FUNCTION ParseDesignator: ADRMEM;
FUNCTION NextKind: Str255;
FUNCTION ParseActualParameterList: ADRMEM;
FUNCTION ParseIdentListArr: ADRMEM;
FUNCTION ParseConstant: ADRMEM;
FUNCTION ParseSetElement: ADRMEM;
FUNCTION ParseFactor: ADRMEM;
FUNCTION ParseTerm: ADRMEM;
FUNCTION ParseSimpleExpression: ADRMEM;
FUNCTION ParseExpression: ADRMEM;
FUNCTION ParseBooleanExpression: ADRMEM;
FUNCTION ParseCaseConstant: ADRMEM;
FUNCTION ParseCaseConstantList: ADRMEM;
FUNCTION ParseIndexRange(allow_star: BOOLEAN): ADRMEM;
FUNCTION ParseSetBase: ADRMEM;
FUNCTION ParseType: ADRMEM;

END;
