{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
PROGRAM CopystrTest;
VAR
    src: STRING(100);
    dest: STRING(256);
BEGIN
    COPYSTR(src, dest)
END.
