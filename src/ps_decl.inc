{ Declaration and compilation-unit parsing for the native parser. }

INTERFACE;
UNIT ps_decl;
USES jsonutil, ps_base, ps_expr, ps_stmt;

FUNCTION ParseAttributeItem: ADRMEM;
FUNCTION ParseAttributeSectionOptional: ADRMEM;
FUNCTION ParseParamGroup: ADRMEM;
FUNCTION ParseParamList: ADRMEM;
PROCEDURE ParseConstSection(decls_arr: ADRMEM);
PROCEDURE ParseTypeSection(decls_arr: ADRMEM);
PROCEDURE ParseVarSection(decls_arr: ADRMEM);
PROCEDURE ParseLabelSection(decls_arr: ADRMEM);
FUNCTION ParseProcDecl: ADRMEM;
FUNCTION ParseFuncDecl: ADRMEM;
PROCEDURE ParseDeclSectionsInto(decls_arr: ADRMEM);
PROCEDURE ParseInterfaceDirectiveInto(node: ADRMEM);
FUNCTION ParseInterfaceProcDecl: ADRMEM;
FUNCTION ParseInterfaceFuncDecl: ADRMEM;
PROCEDURE ParseInterfaceDeclSectionsInto(decls_arr: ADRMEM);
FUNCTION ParseUsesImport: ADRMEM;
PROCEDURE ParseUsesClauseInto(arr: ADRMEM);
FUNCTION IsAtDevicePrefix(target_kind: Str255): BOOLEAN;
FUNCTION ParseModuleUnit(is_device: BOOLEAN): ADRMEM;
FUNCTION ParseInterfaceUnit(is_device: BOOLEAN): ADRMEM;
FUNCTION ParseImplementationUnit(is_device: BOOLEAN): ADRMEM;
FUNCTION ParseBlock: ADRMEM;
FUNCTION ParseProgramUnit: ADRMEM;

END;
